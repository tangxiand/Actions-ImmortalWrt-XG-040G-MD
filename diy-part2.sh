#!/bin/sh
# diy-part2.sh —— 首次启动后的默认配置（NPU 硬件流卸载）
#
# AN7581 的 NPU/PPE 硬件快转需在内网防火墙里打开 flow_offloading_hw 才真正生效。
# 这里把设置写进 uci-defaults，固件首次启动即应用，无需手动开。
# （内核驱动 airoha_eth + NPU 固件 airoha-en7581-npu-firmware 已在 my.config 钉死）
#
# 本脚本在 build.yml 的 "Load custom feeds" 步骤里、cd openwrt 之后执行，
# 因此相对路径 files/ 即 openwrt/files/，会被构建系统原样覆盖进根文件系统。

set -e

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-npu-hw-offload <<'UCI_EOF'
#!/bin/sh
# AN7581 NPU/PPE 硬件流卸载：默认开启，降低转发 CPU 占用
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'
uci -q commit firewall
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/99-npu-hw-offload
echo "OK: NPU 硬件卸载 uci-defaults 已写入（首次启动生效）"
exit 0
