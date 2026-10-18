# PonWrt · Nokia XG-040G-MD (UBI) 一键云编译仓库

本目录是**完整的 GitHub Actions 仓库内容**，commit 到你的 GitHub 仓库后，在 Actions 页面点一次 "Run workflow" 即可编译出带 PON 功能、并集成 iStore 的固件。

## 目录结构（保持原样提交到仓库根目录）

```
your-repo/
├── .github/workflows/build.yml   # 编译工作流（已含 PON 断言 + iStore 集成）
├── feeds.conf.default            # feeds 源：pon_drivers / pon_userspace / istore
└── my.config                     # 你的功能差异项（device + PON + iStore + 常用 App）
```

> 注意：根目录**不要**再放旧的 `.config`（旧的整份 .config 会与官方基线冲突）。本方案用 `configs/an7581.config` 作基线，只把 `my.config` 作为差异项叠加。

## 操作步骤

1. 新建一个 GitHub 仓库（或用你原来跑 Actions 的那个仓库）。
2. 把本目录三个文件按上面的结构放好，commit & push。
3. 仓库 → Settings → Actions → General → "Workflow permissions" 设为 **Read and write permissions**（否则上传 Release / 删旧 Release 会失败）。
4. Actions 标签页 → 选 `Build_nokia_xg-040g-md-ubi` → **Run workflow**。
5. 等约 1.5–3 小时（airoha-pond 是 Rust 程序，需现场编译 rust host 工具链，比普通固件慢）。

## 怎么判断编译成功、PON 真的进包了

日志里会出现这几组关键行（任意一组缺失/报错即失败）：

- `配置阶段断言全部通过` → **必须**出现（约 10 分钟内就能看到，不用等 2.5 小时）
- `设备符号 ... 未生效` → **不能**出现（出现说明回落 EVB）
- `关键包 ... 未生效` / `PON 组件未生效` → **不能**出现
- `PON 核心组件校验通过` → 编译结束后**必须**出现

可选功能解析情况里：
- `[ OK ] luci-app-store` → iStore 已编进固件
- `[MISS] luci-app-store` → 依赖链断了，同一段日志里会打印 iStore 依赖链明细
- `[ OK ] luci-app-socat` → socat 的 LuCI 界面已进包

## 产物位置

- `bin/targets/airoha/an7581/` 下的 `*-nokia_xg-040g-md-ubi-sysupgrade.itb` 即为固件。
- 若开了 `UPLOAD_RELEASE=true`，会在 Release 里下载。

## 刷机与 PON 上线（与编译无关但必须做）

1. 用 [AN758x-Stock2UBI](https://github.com/pbs05/an758x-stock2ubi) 备份原厂并刷入 UBI 布局，U-Boot 用 [AN758x U-Boot](https://github.com/pbs05/uboot-an758x)。
2. 刷完 PonWrt 后，在 LuCI **网络 → PON → 配置 → PON board data** 恢复诺基亚的 `bosa`、`ri` 两个卷（来自原厂备份），否则 PON 口不会注册上线。

## 本次补齐的功能（socat 图形界面 / 动态 DNS / OpenVPN / px5g-mbedtls）

上一版编译成功（约 2.5 小时），但这几项没进固件。iStore 已按要求**移除**，其余补齐：

| 功能 | 上一版状态 | 原因 | 本次处理 |
|---|---|---|---|
| `ddns-go`（DDNS-Go） | **其实已进固件** | — | 保持（服务 → DDNS-Go 可见） |
| 经典「动态 DNS」 | 缺失 | `my.config` 里只钉了 `ddns-scripts`，**漏了 `luci-app-ddns`**（菜单项来自它） | 已补 `luci-app-ddns` + `luci-i18n-ddns-zh-cn` + `ddns-scripts-cloudflare/aliyun` |
| `socat`（**要图形界面**） | 只有命令行、无界面 | 官方 feeds **没有** `luci-app-socat`，socat 本身是纯 CLI | 新增第三方源 `socatapp` + `luci-app-socat`（服务 → Socat），并钉住 Lua 运行前提 `luci-compat / luci-lua-runtime / uhttpd-mod-lua` |
| `OpenVPN` | 缺失 | 没选 | 新增 `openvpn-openssl` + `luci-app-openvpn` + `luci-i18n-openvpn-zh-cn` + `kmod-tun` |
| `px5g-mbedtls` | 未选 | 基线 `configs/an7581.config` 里根本没有 px5g；`uhttpd` 也不再依赖它（DEPENDS 只有 libubox/blobmsg/json 等） | 显式 `CONFIG_PACKAGE_px5g-mbedtls=y`，并关掉 `px5g-wolfssl` / `px5g-openssl` |

> **px5g 为什么要关另外两个**：`px5g-mbedtls`、`px5g-wolfssl`、`px5g-openssl` 都 `PROVIDES:=px5g`，且都要安装 `/usr/sbin/px5g`。同时选中会**文件冲突**，镜像打包阶段直接报错。三者只能留一个，这里留 mbedtls 实现（与 `libmbedtls` 复用，体积更省）。

> **socat 界面是第三方包**（`chenmozhijin/luci-app-socat`，`LUCI_DEPENDS:=+socat +luci +luci-compat`）。若该源拉取失败导致整次构建失败：把 `feeds.conf.default` 里 `src-git socatapp ...` 注释掉，并删 `my.config` 里 `luci-app-socat`、`luci-i18n-socat-zh-cn` 两行即可，其它功能不受影响。

> **socat 图形界面能否显示的前提**：它是 Lua 控制器，必须在 ucode/JS 为主的 LuCI 上挂上 Lua 运行层。本版已钉 `luci-compat`、`luci-lua-runtime`、`uhttpd-mod-lua`。若刷机后「服务 → Socat」菜单不出现，通常是 LuCI 的 Lua 层问题（非编译失败），把日志发我。

### 断言提前了，不会再白等 2.5 小时

`build.yml` 现在在**配置阶段（10 分钟内）**就断言：设备符号、PON 4 件、`px5g-mbedtls`、`luci-app-ddns`、`openvpn-openssl`、`luci-app-openvpn`，以及 `luci-app-socat`。缺任何一个直接 `::error::` 终止，并打印 socat 依赖的 `[OK]/[MISS]` 明细，方便一次定位。

`luci-app-store` / `luci-app-socat` 属"可选集成"，由 `build.yml` 顶部 `REQUIRE_OPTIONAL` 控制：
- `'true'`（默认）：没生效就失败，快速暴露问题；
- `'false'`：只告警、继续出固件。

## 在线安装软件包（apk 源，无需重新编译）

你的固件本身就是 apk 体系，**装完就能在线装包**，不需要再编译进去。原理与验证方式：

1. 构建时 `include/feeds.mk` 的 `FeedSourcesAppendAPK` 会按 `VERSION_REPO` 生成 `/etc/apk/repositories.d/distfeeds.list`；PonWrt 的 `VERSION_REPO` 默认是 `https://downloads.immortalwrt.org/snapshots`（已核实于 `include/version.mk`），目标目录 `targets/airoha/an7581/packages` 与 `packages/aarch64_cortex-a53/{base,luci,packages,routing,telephony}` 都真实存在，且都是 `.apk`。
2. 走 https 必须有 CA 根证书，本次已补 `ca-bundle` + `ca-certificates`（缺它们 `apk update` 会直接报证书错误，这也是很多自制固件"在线安装用不了"的真实原因）。
3. LuCI 里：**系统 → 软件包 → 更新列表**，然后到"可用"页搜索安装。

**必须知道的一个限制**：在线源里的 **kmod（内核模块）装不上**。原因是 vermagic 必须与内核版本精确匹配——你固件是 `6.18.55`，快照仓库里的 kmod 是 `6.18.52~...`，apk 依赖校验会拒绝。**纯用户态插件（LuCI 应用、socat、ddns-go、ttyd、filebrowser 等）可正常安装**；要装 kmod，只能改配置重新编译。

想在设备上手动确认源是否正常：

```sh
cat /etc/apk/repositories.d/distfeeds.list
apk update
apk search luci-app-ttyd | head
```

若要追加自己的源，按官方约定写 `/etc/apk/repositories.d/customfeeds.list`（`distfeeds.list` 是构建生成的，sysupgrade 会覆盖）。

## 常见问题：`固件内缺少 PON 组件： fitblk`

**现象**：Job 跑了 1 个多小时，最后红在"固件内缺少 PON 组件： fitblk"，Artifacts 为空。

**原因**：`fitblk` 是 `package/utils/fitblk` 里的 **`HIDDEN:=1` 隐藏基础包**（依赖 `fit-check-sign`），只作为设备默认包被拉进来，不进菜单；它负责"释放 uImage.FIT 块设备"，**不属于 PON 功能**。部分 apk 构建写出的 `.manifest` 不列隐藏包，于是校验误判。真正决定 PON 的是 `kmod-airoha-xpon`、`kmod-airoha-en7572`、`airoha-ponctl`、`airoha-pond` 这 4 个。

**已修**（build.yml 更新版）：
- 硬校验只针对上述 4 个 PON 核心包；`fitblk` 降级为 `::warning::`，不再判失败；
- manifest 只取本设备那份（`*nokia_xg-040g-md-ubi*`），不再随手抓第一个；
- 新增 `pon-report` 产物，把 manifest 里 `pon/airoha/fit` 相关行、`targets/packages` 里相关包全打出来；
- 所有 Artifacts 上传改成 `always()`，即使后面某步报错，1 小时的镜像也不会再被丢掉。

**想确认设备上是否真有 fitblk**：刷机后 SSH 执行 `ls -l /usr/sbin/fitblk`，或 `apk list --installed | grep fitblk`。

## 关于 socat 图形界面 / OpenVPN 的说明

- **socat 图形界面**：`luci-app-socat` 是第三方 Lua 包。在 ucode/JS 为主的 LuCI 上要让 Lua 控制器跑起来，必须有 `luci-compat` + `luci-lua-runtime` + `uhttpd-mod-lua`，本版已钉住。若刷机后「服务 → Socat」不显示，是 LuCI 的 Lua 运行层问题（不是编译失败），把日志发我即可。
- **OpenVPN**：用 `openvpn-openssl` 实现，复用固件里已选的 `libopenssl`（与 `apk-openssl` 同源），省体积；`kmod-tun` 提供 tun 内核模块；`luci-app-openvpn` 提供「服务 → OpenVPN」配置界面。

iStore 已按你的要求**移除**，相关依赖链不再需要。若日后想加回，按本文件旧版说明重建依赖链即可。

## 想让我以后直接帮你触发编译？

当前对话没有你的 GitHub 凭据，我无法自动 push / 触发 Actions。两种方式可开放给我：
- 在本机装好 `gh` 并 `gh auth login`（或配 PAT），把仓库交给我；
- 或在 WorkBuddy 里连接 GitHub 连接器。
连上后，我可以帮你 git push 并 `gh workflow run` 启动，再把结果回传给你。
