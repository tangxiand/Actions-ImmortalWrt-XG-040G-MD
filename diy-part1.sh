#!/bin/sh
# diy-part1.sh —— 在 feeds 更新时执行的预处理脚本（工作目录 = openwrt）
#
# 作用：把第三方 LuCI 应用 luci-app-socat 直接克隆进 package/。
# 为什么不用 feeds 源：上一轮 CI 里 `src-git socatapp` 这个第三方源没能被 feeds 索引
# （日志报 "feeds 里找不到 luci-app-socat"），直接放进 package/ 更确定、也不依赖 feeds 索引规则。

set -e

if [ -d package/luci-app-socat ]; then
    echo "package/luci-app-socat 已存在，跳过"
    exit 0
fi

TMP="$(mktemp -d)"
echo "克隆 luci-app-socat ..."
if git clone --depth 1 https://github.com/chenmozhijin/luci-app-socat.git "$TMP/repo"; then
    if [ -d "$TMP/repo/luci-app-socat" ]; then
        cp -r "$TMP/repo/luci-app-socat" package/luci-app-socat
    else
        cp -r "$TMP/repo" package/luci-app-socat
    fi
    rm -rf package/luci-app-socat/.git
else
    echo "::warning::luci-app-socat 克隆失败（网络或仓库不可达）"
fi
rm -rf "$TMP"

if [ -f package/luci-app-socat/Makefile ]; then
    echo "OK: package/luci-app-socat/Makefile 就位"
else
    echo "::warning::package/luci-app-socat/Makefile 不存在，socat 图形界面将缺失"
fi

exit 0
