#!/bin/sh
# diy-part1.sh —— 在 feeds 更新时执行的预处理脚本（工作目录 = openwrt）
#
# 作用：把第三方 / 非本 feed 的 LuCI 应用直接克隆进 package/。
# 为什么不用 feeds 源：上一轮 CI 里 `src-git socatapp` 这个第三方源没能被 feeds 索引
# （日志报 "feeds 里找不到 luci-app-socat"），直接放进 package/ 更确定、也不依赖 feeds 索引规则。
#
# 本脚本处理三种仓库布局：
#   1) 仓库内含同名子目录（Makefile 在子目录里）—— 例如 chenmozhijin/luci-app-socat
#   2) 仓库根即包本体（Makefile 在根目录）—— 例如 luanmuc/luci-app-airoha-npu
#   3) 大仓库里某个子目录 + 指定稳定分支 —— 例如 openwrt/luci@openwrt-24.10
#      的 applications/luci-app-openvpn（OpenVPN 客户端界面）
#
# 注意：脚本本身“尽力克隆、不致命失败”。真正的成败由 build.yml 配置阶段的断言决定
# （REQUIRE_OPTIONAL 控制 luci-app-socat / luci-app-airoha-npu / luci-app-openvpn
#  缺失时是否 fail）。

set -e

clone_pkg() {
    # $1 = 仓库 URL； $2 = package/ 下的目标目录名
    repo_url="$1"
    dest="$2"

    if [ -d "package/$dest" ]; then
        echo "package/$dest 已存在，跳过克隆"
        return 0
    fi

    TMP="$(mktemp -d)"
    echo "克隆 $dest ..."
    if git clone --depth 1 "$repo_url" "$TMP/repo" 2>/dev/null; then
        # 布局 A：仓库根即包本体（Makefile 在根目录）
        if [ -f "$TMP/repo/Makefile" ]; then
            cp -r "$TMP/repo" "package/$dest"
        # 布局 B：仓库内含同名子目录（Makefile 在子目录里）
        elif [ -f "$TMP/repo/$dest/Makefile" ]; then
            cp -r "$TMP/repo/$dest" "package/$dest"
        else
            echo "::warning::$dest 克隆后未找到 Makefile（仓库布局未知，跳过）"
            rm -rf "$TMP"
            return 1
        fi
        # 丢掉 .git，避免把仓库历史带进固件源码树
        rm -rf "package/$dest/.git"
        if [ -f "package/$dest/Makefile" ]; then
            echo "OK: package/$dest/Makefile 就位"
        else
            echo "::warning::package/$dest/Makefile 不存在（克隆异常）"
        fi
    else
        echo "::warning::$dest 克隆失败（网络或仓库不可达）—— 配置阶段断言会暴露此问题"
    fi
    rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# OpenVPN 客户端界面：从 openwrt/luci 的 openwrt-24.10 稳定分支单独取一个包
# ---------------------------------------------------------------------------
# 背景：immortalwrt/luci master 只有 luci-app-openvpn-server（服务端），
#       openwrt/luci master 也已移除 luci-app-openvpn；但 openwrt-24.10 分支仍保留
#       applications/luci-app-openvpn（LUCI_TITLE:=LuCI Support for OpenVPN）。
#       它提供「VPN → OpenVPN」页：编辑 sample_client / 上传 .ovpn / 启停客户端实例。
# 冲突核对：该包只安装 /etc/config/openvpn_recipes + LuCI Lua 文件；
#       luci-app-openvpn-server 安装的是 /etc/config/openvpn，两者不冲突。
clone_openvpn_client() {
    dest="luci-app-openvpn"
    if [ -d "package/$dest" ]; then
        echo "package/$dest 已存在，跳过克隆"
        return 0
    fi

    TMP="$(mktemp -d)"
    echo "克隆 $dest（openwrt/luci@openwrt-24.10/applications/luci-app-openvpn）..."
    if git clone --depth 1 --single-branch --branch openwrt-24.10 \
        https://github.com/openwrt/luci.git "$TMP/repo" 2>/dev/null; then
        src="$TMP/repo/applications/$dest"
        if [ -f "$src/Makefile" ]; then
            cp -r "$src" "package/$dest"
            rm -rf "package/$dest/.git"
            # 上游 Makefile 用相对路径 include ../../luci.mk（luci 仓库内布局）。
            # 放进 buildroot 的 package/ 后该路径失效，改成 feeds 里的绝对路径。
            # 注意用单引号包住 sed 表达式，避免 shell 把 $(TOPDIR) 当命令替换。
            sed -i 's|^include \.\./\.\./luci\.mk|include $(TOPDIR)/feeds/luci/luci.mk|' \
                "package/$dest/Makefile"
            if grep -q 'include $(TOPDIR)/feeds/luci/luci.mk' "package/$dest/Makefile"; then
                echo "OK: package/$dest/Makefile 就位，且 luci.mk include 已修正"
            else
                echo "::warning::package/$dest 的 luci.mk include 未修正（配置阶段断言会暴露）"
            fi
        else
            echo "::warning::未找到 applications/$dest/Makefile（上游分支结构变化？）"
        fi
    else
        echo "::warning::$dest 克隆失败（网络或仓库不可达）—— 配置阶段断言会暴露此问题"
    fi
    rm -rf "$TMP"
}

# 1) socat 图形界面（服务 → Socat），第三方 Lua 应用，含同名子目录
clone_pkg "https://github.com/chenmozhijin/luci-app-socat.git" "luci-app-socat" || true

# 2) NPU 状态监控页（状态 → Airoha SoC Status），仓库根即包本体，与官方固件同源（v1.2.1）
#    仅做监控/CPU 频率/PPE 流表展示，不负责开启硬件加速（加速由 NPU 固件 + flow_offloading_hw 负责）。
#    运行时依赖 devmem（busybox），已在 my.config 设 CONFIG_BUSYBOX_CONFIG_DEVMEM / CONFIG_BUSYBOX_CUSTOM。
clone_pkg "https://github.com/luanmuc/luci-app-airoha-npu.git" "luci-app-airoha-npu" || true

# 3) OpenVPN 客户端界面（VPN → OpenVPN），来自 openwrt/luci 的 openwrt-24.10 分支
clone_openvpn_client || true

exit 0
