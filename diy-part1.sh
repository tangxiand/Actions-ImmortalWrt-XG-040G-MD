#!/bin/sh
# diy-part1.sh —— 在 feeds 更新时执行的预处理脚本（工作目录 = openwrt）
#
# 作用：把第三方 LuCI 应用直接克隆进 package/。
# 为什么不用 feeds 源：上一轮 CI 里 `src-git socatapp` 这个第三方源没能被 feeds 索引
# （日志报 "feeds 里找不到 luci-app-socat"），直接放进 package/ 更确定、也不依赖 feeds 索引规则。
#
# 本脚本同时处理两种仓库布局：
#   1) 仓库内含同名子目录（Makefile 在子目录里）—— 例如 chenmozhijin/luci-app-socat
#   2) 仓库根即包本体（Makefile 在根目录）—— 例如 luanmuc/luci-app-airoha-npu
#
# 注意：脚本本身“尽力克隆、不致命失败”。真正的成败由 build.yml 配置阶段的断言决定
# （REQUIRE_OPTIONAL 控制 luci-app-socat / luci-app-airoha-npu 缺失时是否 fail）。

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

# 1) socat 图形界面（服务 → Socat），第三方 Lua 应用，含同名子目录
clone_pkg "https://github.com/chenmozhijin/luci-app-socat.git" "luci-app-socat" || true

# 2) NPU 状态监控页（状态 → Airoha SoC Status），仓库根即包本体，与官方固件同源（v1.2.1）
#    仅做监控/CPU 频率/PPE 流表展示，不负责开启硬件加速（加速由 NPU 固件 + flow_offloading_hw 负责）。
#    运行时依赖 devmem（busybox），已在 my.config 设 CONFIG_BUSYBOX_CONFIG_DEVMEM / CONFIG_BUSYBOX_CUSTOM。
clone_pkg "https://github.com/luanmuc/luci-app-airoha-npu.git" "luci-app-airoha-npu" || true

exit 0
