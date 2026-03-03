#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Uncomment a feed source
# sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# 关键：检查并确保feeds.conf.default中iStore源存在（避免重复添加）
if ! grep -q "istore" feeds.conf.default; then
    echo "src-git istore https://github.com/linkease/istore;main" >> feeds.conf.default
fi

# 强制更新feeds索引（确保拉取最新的软件包）
./scripts/feeds update -a
