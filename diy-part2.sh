#!/bin/sh
# diy-part2.sh —— 自定义 rootfs 文件 + 首次启动默认配置
#
# 本脚本在 build.yml 的 "Load custom feeds" 步骤里、cd openwrt 之后执行，
# 因此相对路径 files/ 即 openwrt/files/，会被构建系统原样覆盖进根文件系统。
#
# 产出（均为纯 rootfs 文件，不改内核 / 不改 LuCI 源码）：
#   files/usr/lib/pon-tempinfo/tempinfo       概览页「温度」行数据源（CPU + PON）
#   files/etc/uci-defaults/97-pon-tempinfo    首启安装 /sbin/tempinfo
#   files/etc/uci-defaults/98-fix-apk-repos   首启剔除 404 的 apk 源
#   files/etc/uci-defaults/99-npu-hw-offload  首启开启 NPU 硬件流卸载

set -e

mkdir -p files/etc/uci-defaults files/usr/lib/pon-tempinfo

# ===========================================================================
# 1) 概览页「温度」行：CPU + PON 光前端温度
# ===========================================================================
# 调用链（已核对上游源码，非猜测）：
#   luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#       -> rpc.declare({ object: 'luci', method: 'getTempInfo' })
#       -> 若 tempinfo.tempinfo 非空，插入「温度」行，值原样显示
#   immortalwrt/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci
#       getTempInfo: popen('/sbin/tempinfo')，返回其 stdout
#   所以只要 /sbin/tempinfo 输出 "CPU: 59.1°C | PON: 41.5°C"，概览页就会显示。
#
# CPU 数据源：/sys/class/thermal/thermal_zone*/temp（毫摄氏度）
#   -> my.config 已钉 CONFIG_THERMAL=y + CONFIG_AIROHA_THERMAL=y
# PON 数据源：/usr/sbin/ponctl ... status --json -> frontend.temperature_celsius
#   与 LuCI「网络 → PON → 状态」里的「光前端温度 41.47 °C」是同一个字段。
#   依据：
#     pbs05/openwrt-pon-userspace/luci-app-pon/.../view/pon/status.js
#       fs.exec_direct('/usr/sbin/ponctl', ['--device', device, 'status', '--json'])
#       row(_('Optical frontend temperature'),
#           displayFrontendMetric(frontend, 'temperature_celsius', '°C'))
#     pbs05/openwrt-pon-userspace/airoha-ponctl/src/src/status.rs
#       convert_optics(): ("temperature_8472", "temperature_celsius", 1.0/256.0)
#   注意：PON 温度【不是】内核 thermal zone，而是光模块 DDM 寄存器，
#         所以上一版"等设备树暴露 PON 热区"的思路是错的，改由本脚本读取。
cat > files/usr/lib/pon-tempinfo/tempinfo <<'TEMPINFO_EOF'
#!/bin/sh
# PON_TEMPINFO_V1 — LuCI 概览页「温度」行：CPU + PON 光前端温度
# 由 diy-part2.sh 注入；uci-defaults/97-pon-tempinfo 首启复制到 /sbin/tempinfo

fmt_c() { [ -r "$1" ] && awk '{printf("%.1f°C", $0 / 1000)}' "$1" 2>/dev/null; }
f1()    { [ -n "$1" ] && awk -v v="$1" 'BEGIN { printf("%.1f", v) }' 2>/dev/null; }

# ---- CPU：内核热区，单位毫摄氏度（取第一个可读热区）----
cpu=""
for z in /sys/class/thermal/thermal_zone*/temp; do
	[ -r "$z" ] || continue
	cpu="$(fmt_c "$z")"
	[ -n "$cpu" ] && break
done

# ---- PON：光模块 DDM（与「网络 → PON → 状态」的「光前端温度」同源）----
pon=""
if [ -x /usr/sbin/ponctl ]; then
	dev="$(/sbin/uci -q get pon.@xpon[0].device 2>/dev/null)"
	if [ -n "$dev" ]; then
		js="$(/usr/sbin/ponctl --device "$dev" status --json 2>/dev/null)"
	else
		js="$(/usr/sbin/ponctl status --json 2>/dev/null)"
	fi
	if [ -n "$js" ] && [ -x /usr/bin/jsonfilter ]; then
		v="$(printf '%s' "$js" | /usr/bin/jsonfilter -q -e '@.frontend.temperature_celsius' 2>/dev/null)"
		[ -n "$v" ] && pon="$(f1 "$v")"
	fi
fi

# ---- 组装（用户参考固件的格式：CPU: 60.5°C | PON: 46.3°C）----
out=""
[ -n "$cpu" ] && out="CPU: $cpu"
[ -n "$pon" ] && out="${out:+$out | }PON: ${pon}°C"
[ -n "$out" ] || out="No temperature info"
printf '%s' "$out"
TEMPINFO_EOF
chmod +x files/usr/lib/pon-tempinfo/tempinfo

# 用 uci-defaults 显式复制，避免依赖「构建系统 files/ 与包安装」的覆盖先后顺序
cat > files/etc/uci-defaults/97-pon-tempinfo <<'UCI_EOF'
#!/bin/sh
# 首启安装概览页温度数据源（CPU + PON）
SRC=/usr/lib/pon-tempinfo/tempinfo
DST=/sbin/tempinfo
if [ -f "$SRC" ]; then
	cp -f "$SRC" "$DST" && chmod 755 "$DST"
	logger -t pon-tempinfo "installed $DST (CPU + PON temperature)"
else
	logger -t pon-tempinfo "WARN: $SRC missing, temperature line unchanged"
fi
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/97-pon-tempinfo

# ===========================================================================
# 2) apk 更新列表：剔除指向不存在目录的自定义 feed 源
# ===========================================================================
# 根因（用户 2026-11-07 截图）：
#   ERROR: wget: exited with error 8
#   WARNING: updating and opening https://downloads.immortalwrt.org/snapshots/
#            packages/aarch64_cortex-a53/{istore,pon_drivers,pon_userspace,video}
#            /packages.adb: unexpected end of file
#   apk update 命令失败了，代码为 4 → LuCI 前端 SyntaxError: Unexpected end of JSON input
#
# 依据 immortalwrt/immortalwrt/include/feeds.mk 的 FeedSourcesAppendAPK：
#   为每个启用的 feed 生成 '%U/packages/%A/$(feed)/packages.adb'
# 而 downloads.immortalwrt.org 只托管 base/luci/packages/routing/telephony（+targets）。
# pon_drivers / pon_userspace（PonWrt 私有源）、istore（iStoreOS）、video 都是
# 本地 feed，服务器上没有对应目录 → 404 → apk update 整体返回非零。
# 官方 5 个源其实更新成功（日志 "10220 distinct packages available"）。
#
# 用 awk 注释掉这 4 条（幂等：已注释的行原样跳过），保留其余全部源。
cat > files/etc/uci-defaults/98-fix-apk-repos <<'UCI_EOF'
#!/bin/sh
# 首启剔除构建自动生成、但上游服务器不存在的自定义 feed 源
LIST=/etc/apk/repositories.d/distfeeds.list
[ -f "$LIST" ] || exit 0

awk '
	/^[[:space:]]*#/ { print; next }
	/\/pon_drivers\/packages\.adb/   ||
	/\/pon_userspace\/packages\.adb/ ||
	/\/istore\/packages\.adb/        ||
	/\/video\/packages\.adb/ { print "# " $0; next }
	{ print }
' "$LIST" > "$LIST.tmp" && mv -f "$LIST.tmp" "$LIST"
chmod 644 "$LIST"

logger -t fix-apk-repos "active apk sources after cleanup:"
grep -v '^[[:space:]]*#' "$LIST" | while IFS= read -r line; do
	[ -n "$line" ] && logger -t fix-apk-repos "  $line"
done
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/98-fix-apk-repos

# ===========================================================================
# 3) NPU / PPE 硬件流卸载：首次启动自动开启
# ===========================================================================
# AN7581 的 NPU/PPE 硬件快转需在内网防火墙里打开 flow_offloading_hw 才真正生效。
# （内核驱动 airoha_eth + NPU 固件 airoha-en7581-npu-firmware 已在 my.config 钉死）
cat > files/etc/uci-defaults/99-npu-hw-offload <<'UCI_EOF'
#!/bin/sh
# AN7581 NPU/PPE 硬件流卸载：默认开启，降低转发 CPU 占用
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'
uci -q commit firewall
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/99-npu-hw-offload

echo "OK: diy-part2.sh 已写入 4 个自定义文件"
echo "    - files/usr/lib/pon-tempinfo/tempinfo      (CPU + PON 温度)"
echo "    - files/etc/uci-defaults/97-pon-tempinfo   (安装 /sbin/tempinfo)"
echo "    - files/etc/uci-defaults/98-fix-apk-repos  (清理 404 的 apk 源)"
echo "    - files/etc/uci-defaults/99-npu-hw-offload (开启 NPU 硬件卸载)"
exit 0
