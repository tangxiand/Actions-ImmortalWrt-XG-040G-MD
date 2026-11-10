# PonWrt · Nokia XG-040G-MD (UBI) 一键云编译仓库

本目录是**完整的 GitHub Actions 仓库内容**，commit 到你的 GitHub 仓库后，在 Actions 页面点一次 "Run workflow" 即可编译出带 PON 功能，并集成 socat 图形界面 / OpenVPN 服务端+客户端 / px5g-mbedtls / NPU 硬件加速 / DoH / 概览页 CPU+PON 温度的固件。DDNS 与 ddns-go 已按 2026-11-10 要求移除。

## 2026-11-10 本轮变更

| 需求 | 处理 |
|---|---|
| 加 OpenVPN **客户端** | 新增 `luci-app-openvpn` + `luci-i18n-openvpn-zh-cn`（从 `openwrt/luci@openwrt-24.10` 单独取包进 `package/`）；服务端 `luci-app-openvpn-server` 保留、两者不冲突 |
| 取消「动态域名解析」和 `ddns-go` | `my.config` 用显式 `# CONFIG_PACKAGE_* is not set` 关掉 9 个符号（构建是「基线 + 差异项叠加」，只删 `=y` 行不够）；`build.yml` 配置阶段校验无残留 |
| 显示 CPU / PON 温度 | **保持不变**：`diy-part2.sh` 注入的 `/sbin/tempinfo`（CPU 热区 + `ponctl status --json` 的 `frontend.temperature_celsius`）；本轮把 `jsonfilter` 加进配置阶段硬断言 |
| 确保软件源可用 | **编译期主修**：`CONFIG_FEED_{pon_drivers,pon_userspace,istore,video}=m`，让 4 条 404 源在生成 `distfeeds.list` 时即被注释；首启 `98-fix-apk-repos` 继续兜底 |
| 其他 | NPU 硬件加速、DoH、iStore（软失败）、socat、ZeroTier、WOL、主题等一律保持不变 |

## 目录结构（保持原样提交到仓库根目录）

```
your-repo/
├── .github/workflows/build.yml   # 编译工作流（PON 断言 + OpenVPN 服务端/客户端 + socat + NPU/DoH）
├── feeds.conf.default            # feeds 源：pon_drivers / pon_userspace / istore（socat 不再走此文件）
├── diy-part1.sh                  # 预处理脚本：克隆 luci-app-socat / luci-app-airoha-npu / luci-app-openvpn 进 package/
├── diy-part2.sh                  # 注入自定义 rootfs 文件 + 首启脚本（温度 CPU+PON / apk 源清理 / NPU 卸载）
└── my.config                     # 功能差异项（device + PON + OpenVPN 服务端/客户端 + socat + NPU + DoH；DDNS 显式关闭）
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
- `[ OK ] luci-app-socat` → socat 的 LuCI 界面已进包（由 diy-part1.sh 克隆进 package/）
- `[ OK ] luci-app-openvpn-server` → OpenVPN **服务端**界面
- `[ OK ] luci-app-openvpn` → OpenVPN **客户端**界面（从 openwrt/luci 稳定分支单独取，见下方专节）
- `[ OK ] px5g-mbedtls` / `[ OK ] jsonfilter` → 已进包
- `DDNS / DDNS-Go 已全部移除` → 确认两套 DDNS 没被基线或依赖拉回
- 4 条 `[ OK ] CONFIG_FEED_*=m` → 404 源在编译期即被注释，软件源可用

## 产物位置

- `bin/targets/airoha/an7581/` 下的 `*-nokia_xg-040g-md-ubi-sysupgrade.itb` 即为固件。
- 若开了 `UPLOAD_RELEASE=true`，会在 Release 里下载。

## 刷机与 PON 上线（与编译无关但必须做）

1. 用 [AN758x-Stock2UBI](https://github.com/pbs05/an758x-stock2ubi) 备份原厂并刷入 UBI 布局，U-Boot 用 [AN758x U-Boot](https://github.com/pbs05/uboot-an758x)。
2. 刷完 PonWrt 后，在 LuCI **网络 → PON → 配置 → PON board data** 恢复诺基亚的 `bosa`、`ri` 两个卷（来自原厂备份），否则 PON 口不会注册上线。

## 历史补齐记录（socat 图形界面 / OpenVPN / px5g-mbedtls）

上一版编译成功（约 2.5 小时），但这几项没进固件；iStore 当时按要求移除，后于 2026-11-07 重新集成（见下方「iStore 应用商店」）。其余补齐：

| 功能 | 上一版状态 | 原因 | 本次处理 |
|---|---|---|---|
| `socat`（**要图形界面**） | 只有命令行、无界面 | 官方 feeds **没有** `luci-app-socat`，socat 本身是纯 CLI | 新增 `diy-part1.sh` 把第三方 `luci-app-socat` 直接克隆进 `package/`（服务 → Socat），并钉住 Lua 运行前提 `luci-compat / luci-lua-runtime / uhttpd-mod-lua` |
| `OpenVPN` 服务端 | 缺失 | 没选 | 新增 `openvpn-openssl` + `openvpn-easy-rsa` + `luci-app-openvpn-server` + `luci-i18n-openvpn-server-zh-cn` + `kmod-tun` |
| `OpenVPN` 客户端 | 缺失 | immortalwrt/luci master 与 openwrt/luci master 都没有 `luci-app-openvpn` | 2026-11-10 从 `openwrt/luci@openwrt-24.10` 单独取该包进 `package/`（见下方专节） |
| `px5g-mbedtls` | 未选 | 基线 `configs/an7581.config` 里根本没有 px5g；`uhttpd` 也不再依赖它（DEPENDS 只有 libubox/blobmsg/json 等） | 显式 `CONFIG_PACKAGE_px5g-mbedtls=y`，并关掉 `px5g-wolfssl` / `px5g-openssl` |
| DDNS / DDNS-Go | 曾有 | — | **2026-11-10 按要求全部移除**（`my.config` 用显式 `is not set`，见下方专节） |

> **px5g 为什么要关另外两个**：`px5g-mbedtls`、`px5g-wolfssl`、`px5g-openssl` 都 `PROVIDES:=px5g`，且都要安装 `/usr/sbin/px5g`。同时选中会**文件冲突**，镜像打包阶段直接报错。三者只能留一个，这里留 mbedtls 实现（与 `libmbedtls` 复用，体积更省）。

> **socat 界面是第三方包**（`chenmozhijin/luci-app-socat`，`LUCI_DEPENDS:=+socat +luci +luci-compat`，Makefile 用 `include $(TOPDIR)/feeds/luci/luci.mk`，放进 `package/` 也能正确编译）。若克隆失败导致整次构建失败：把 `diy-part1.sh` 里 socat 克隆段注释掉，并删 `my.config` 里 `luci-app-socat`、`luci-i18n-socat-zh-cn` 两行即可，其它功能不受影响。（`feeds.conf.default` 里的 `src-git socatapp` 已默认注释掉，无需再动。）

> **socat 图形界面能否显示的前提**：它是 Lua 控制器，必须在 ucode/JS 为主的 LuCI 上挂上 Lua 运行层。本版已钉 `luci-compat`、`luci-lua-runtime`、`uhttpd-mod-lua`。若刷机后「服务 → Socat」菜单不出现，通常是 LuCI 的 Lua 层问题（非编译失败），把日志发我。

### 断言提前了，不会再白等 2.5 小时

`build.yml` 现在在**配置阶段（10 分钟内）**就断言：设备符号、PON 4 件、`px5g-mbedtls`、`jsonfilter`（温度脚本解析 ponctl JSON 必需）、`openvpn-openssl` + `openvpn-easy-rsa` + `luci-app-openvpn-server`、`airoha-en7581-npu-firmware` + `kmod-nft-offload`、`https-dns-proxy` + `luci-app-https-dns-proxy`。缺任何一个直接 `::error::` 终止。另有 3 组诊断输出：`DDNS 已全部移除`、`CONFIG_FEED_*=m`（软件源）、第三方 `package/` 包的 `[OK]/[MISS]` 明细。

`luci-app-socat` / `luci-app-airoha-npu` / `luci-app-openvpn` 这三个「直接克隆进 `package/`」的包属"可选集成"，由 `build.yml` 顶部 `REQUIRE_OPTIONAL` 控制：
- `'true'`（默认）：没生效就失败，快速暴露问题；
- `'false'`：只告警、继续出固件。

`luci-app-store`（iStore）属"软失败 / best-effort"，由 `build.yml` 顶部 `REQUIRE_ISTORE` 控制：
- `'false'`（默认）：iStore **不会**阻断编译——源克隆失败或依赖不满足时只告警、继续出固件（NPU/DoH/温度等核心功能不受影响）；若成功加载则自动进包。
- `'true'`：强制——iStore 没集成就 `::error::` 终止，用于定位必须修的根因。
- 另外，Update feeds 阶段会对 istore 源**单独重试 3 次**，专门规避 GitHub 偶发限流导致的克隆失败（这是本次 `luci-app-store` 未生效的最可能原因）。若仍缺失，配置阶段日志的 `::group::iStore 集成诊断` 会打印「feed 缺失」还是「依赖未满足」，据此判断根因。

## 在线安装软件包（apk 源，无需重新编译）

> **2026-11-07 已修复「软件更新不可用」**：上一版 `apk update` 报
> `ERROR: wget: exited with error 8` / `unexpected end of file`、失败代码 4，
> LuCI 弹 `SyntaxError: Unexpected end of JSON input`。根因不是网络或证书，
> 而是构建自动生成的 `distfeeds.list` 里有 **4 条指向不存在目录的源**
> （`istore` / `pon_drivers` / `pon_userspace` / `video`）。详见本节的「更新列表失败」小节。

你的固件本身就是 apk 体系，**装完就能在线装包**，不需要再编译进去。原理与验证方式：

1. 构建时 `include/feeds.mk` 的 `FeedSourcesAppendAPK` 会按 `VERSION_REPO` 生成 `/etc/apk/repositories.d/distfeeds.list`；PonWrt 的 `VERSION_REPO` 默认是 `https://downloads.immortalwrt.org/snapshots`（已核实于 `include/version.mk`），目标目录 `targets/airoha/an7581/packages` 与 `packages/aarch64_cortex-a53/{base,luci,packages,routing,telephony}` 都真实存在，且都是 `.apk`。
2. 走 https 必须有 CA 根证书，本次已补 `ca-bundle` + `ca-certificates`（缺它们 `apk update` 会直接报证书错误，这也是很多自制固件"在线安装用不了"的真实原因）。
3. LuCI 里：**系统 → 软件包 → 更新列表**，然后到"可用"页搜索安装。
4. **编译期修复（2026-11-10，确保软件源可用）**：`my.config` 把 `CONFIG_FEED_{pon_drivers,pon_userspace,istore,video}=m`。依据 `scripts/feeds` 的 `feed_config()`（`tristate`，帮助文字原句 `Say M to add the feed commented out.`）与 `include/feeds.mk` 的 `FeedSourcesAppendAPK`（`=m` 时输出以 `# ` 开头的 `%U/packages/%A/<feed>/packages.adb`），这 4 条本地 feed 的源**在生成 distfeeds.list 时就已被注释**，烤进镜像的固件天然没有 404 源。`=m` 只影响「是否写进源列表」，**不影响**该 feed 的包被选中/编译（`scripts/feeds install -a` 按 feeds.conf 全量安装，与 `CONFIG_FEED_*` 无关）。`CONFIG_PER_FEED_REPO=y` 是这些符号的 depends 前提，已显式钉住。

**必须知道的一个限制**：在线源里的 **kmod（内核模块）装不上**。原因是 vermagic 必须与内核版本精确匹配——你固件是 `6.18.55`，快照仓库里的 kmod 是 `6.18.52~...`，apk 依赖校验会拒绝。**纯用户态插件（LuCI 应用、socat、ttyd、filebrowser 等）可正常安装**；要装 kmod，只能改配置重新编译。

想在设备上手动确认源是否正常：

```sh
cat /etc/apk/repositories.d/distfeeds.list
apk update
apk search luci-app-ttyd | head
```

若要追加自己的源，按官方约定写 `/etc/apk/repositories.d/customfeeds.list`（`distfeeds.list` 是构建生成的，sysupgrade 会覆盖）。

### 「更新列表」失败：`wget: exited with error 8` / `apk update 命令失败了，代码为 4`

**根因**（依据 `immortalwrt/immortalwrt/include/feeds.mk` 的 `FeedSourcesAppendAPK`）：
构建时会为 `feeds.conf.default` 里**每个启用的 feed** 生成一条
`https://downloads.immortalwrt.org/snapshots/packages/aarch64_cortex-a53/<feed>/packages.adb`。
而官方下载站只托管 `base` / `luci` / `packages` / `routing` / `telephony`（加 `targets/...`）。
本仓库的 4 个本地 feed —— `pon_drivers`、`pon_userspace`（PonWrt 私有）、`istore`（iStoreOS）、`video` ——
在服务器上**没有对应目录**，返回 404，于是 `apk update` 整体返回非零，LuCI 前端拿到非 JSON 输出就报
`SyntaxError: Unexpected end of JSON input`。日志里的 `4 unavailable, 0 stale; 10220 distinct packages available`
恰恰说明：**官方 5 个源是成功的**，只有这 4 条拖累了整体退出码。

**两层修复（2026-11-10 起）**：
1. **编译期（主）**：`my.config` 的 `CONFIG_FEED_*=m` 让这 4 条源在构建生成 `distfeeds.list` 时就被注释，镜像里天然可用；`build.yml` 配置阶段会打印 4 条 `[ OK ] CONFIG_FEED_*=m`。
2. **首启（兜底）**：`diy-part2.sh` 写入的 `files/etc/uci-defaults/98-fix-apk-repos` 幂等注释掉任何残留的这 4 条源（兼容 sysupgrade 保留旧配置的情况），其余源全部保留。

**当前这台设备不想重编译，直接 SSH 执行**（与自动修复等价）：

```sh
LIST=/etc/apk/repositories.d/distfeeds.list
awk '
  /^[[:space:]]*#/ { print; next }
  /\/pon_drivers\/packages\.adb/ || /\/pon_userspace\/packages\.adb/ ||
  /\/istore\/packages\.adb/      || /\/video\/packages\.adb/ { print "# " $0; next }
  { print }
' "$LIST" > "$LIST.tmp" && mv -f "$LIST.tmp" "$LIST"
apk update
```

`distfeeds.list` 是构建生成的、sysupgrade 会覆盖；若以后 sysupgrade 保留配置且「更新列表」又失败，
重跑上面这段即可（新编译的固件自带首启自动清理）。

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
- **OpenVPN 服务端**：用 `openvpn-openssl` 实现，复用固件里的 `libopenssl`，省体积；`openvpn-easy-rsa` 提供证书工具；`kmod-tun` 提供 tun 内核模块；服务端界面包名是 `luci-app-openvpn-server`（服务 → OpenVPN Server）。
- **OpenVPN 客户端**：见下方「OpenVPN 客户端界面」专节——`luci-app-openvpn`（VPN → OpenVPN），与服务端并存、不冲突。

### OpenVPN 客户端界面（VPN → OpenVPN）

按你 2026-11-10 的要求，在已有服务端之外补上客户端界面。

- **包名**：`luci-app-openvpn` + `luci-i18n-openvpn-zh-cn`（中文）。
- **来源**：`immortalwrt/luci` master 与 `openwrt/luci` master 都已移除该包，但 **`openwrt/luci` 的 `openwrt-24.10` 稳定分支**仍保留 `applications/luci-app-openvpn`（`LUCI_TITLE:=LuCI Support for OpenVPN`、`LUCI_DEPENDS:=+luci-base +luci-compat`、`po/zh_Hans/openvpn.po` 齐全）。`diy-part1.sh` 从该分支单独把这个目录克隆进 `package/`，并把上游 Makefile 的 `include ../../luci.mk` 改成 `include $(TOPDIR)/feeds/luci/luci.mk`（放进 buildroot 的 `package/` 后相对路径会失效）。
- **能力**：菜单 **VPN → OpenVPN**，可编辑 `sample_client`、用「OVPN configuration file upload」上传 `.ovpn` 建客户端实例，勾选 Enabled 后 Start/Stop。上游 `luasrc/controller/openvpn.lua` 注册 `admin/vpn/openvpn`，`ovpn_upload()` 把文件写到 `/etc/openvpn/<name>.ovpn` 并在 `/etc/config/openvpn` 里建实例；模板来自 `/etc/config/openvpn_recipes`。
- **与服务端不冲突**：客户端包只安装 `/etc/config/openvpn_recipes` + LuCI Lua 文件；服务端包 `luci-app-openvpn-server` 安装的是 `/etc/config/openvpn`，菜单也在不同位置。二者共用已有的 `openvpn-openssl` 可执行文件。
- **运行前提**：它是 Lua/CBI 应用，`luci-compat` / `luci-lua-runtime` / `uhttpd-mod-lua` 本配置已钉住。
- **成败保障**：`build.yml` 的 `REQUIRE_OPTIONAL`（默认 `'true'`）在配置阶段校验 `CONFIG_PACKAGE_luci-app-openvpn`；克隆失败或 include 未修正会在 10 分钟内红掉，不会白跑 2.5 小时。Load custom feeds 步骤还会检查 include 是否被修正。
- **刷机后**：若菜单没出现，先 `/etc/init.d/rpcd restart` 再重新登录 LuCI（Lua 控制器菜单需 rpcd 重载）。客户端要真正上网，还需按常规做法给 tun0 建接口 + 防火墙区域（Masquerading + LAN→VPN 转发），这与编译无关。

### DDNS / DDNS-Go 已移除（2026-11-10）

- `my.config` 里 9 个符号全部改为显式 `# CONFIG_PACKAGE_xxx is not set`：`ddns-scripts{,-services,-cloudflare,-aliyun}`、`luci-app-ddns`、`luci-i18n-ddns-zh-cn`、`ddns-go`、`luci-app-ddns-go`、`luci-i18n-ddns-go-zh-cn`。
- **为什么必须写成 `is not set`**：构建是「`configs/an7581.config` 基线 + `my.config` 差异项叠加」，`build.yml` 会把同名符号的 `=y` 行删掉再追加我方行；只删 `=y` 行的话，基线里若带同名符号仍会生效。`make defconfig` 也尊重 `is not set`。
- **顺带修掉一个真 bug**：`build.yml` 原来用 `[A-Za-z0-9_]+` 从 `# CONFIG_XXX is not set` 里提取符号，**连字符不在字符类里**，于是所有带 `-` 的包名（`ddns-go`、`luci-app-ddns`，以及原有的 `px5g-wolfssl` / `px5g-openssl`）都被整行跳过、基线里的 `=y` 根本没被删掉。已改成 `[A-Za-z0-9_-]+`。模拟实测：9 条 DDNS 关闭行 + 2 条 px5g 关闭行都能正确覆盖基线 `=y`。
- **校验**：`build.yml` 配置阶段会检查 `ddns-go / luci-app-ddns-go / ddns-scripts / luci-app-ddns` 是否仍为 `=y|m`，有残留则 `::warning::`（通常是被别的包依赖拉回），否则打印 `DDNS / DDNS-Go 已全部移除`。

### iStore 应用商店（服务 → iStore，包名 luci-app-store）

按你 2026-11-07 的要求重新集成（之前按要求移除过）。菜单里叫「iStore」，版本 `0.2.1-r1`，与你现有固件一致。

- **来源**：`feeds.conf.default` 里的 `src-git istore https://github.com/istoreos/istore.git;main`（iStoreOS 官方源）。只需选 `luci-app-store`，它的 `LUCI_DEPENDS` 自动拉 `curl` / `tar` / `libuci-lua` / `mount-utils` / `luci-lib-taskd`；`luci-lib-taskd` 再拉 `luci-lib-xterm` + `taskd`（后端守护进程）。`luci-compat` 本配置已含（19.07+ 必需）。
- **apk 支持**：该包 Makefile 含 `USE_APK`，对 apk 体系做了适配，可在本固件的 apk 上正常安装/卸载插件。
- **编译注意**：构建时会从 GitHub 下载 `istore-ui` 前端 tarball（linkease/istore-ui），所以 `make download` 阶段需联网；若 download 失败会红在下载环节。
- **集成策略（best-effort，不阻断编译）**：`build.yml` 对 istore 源做 Update feeds 单独重试 3 次；`luci-app-store` 默认**不**参与硬断言——源克隆失败或依赖未满足时只告警、继续出固件（NPU/DoH/温度等核心功能不受影响）。若你**必须**要 iStore，把 `build.yml` 顶部 `REQUIRE_ISTORE` 改成 `'true'` 即可让它在缺失时红掉。缺失时的根因会由日志里的 `::group::iStore 集成诊断` 输出（feed 缺失 / 依赖未满足）。
- **刷机后验证**：LuCI **服务 → iStore** 可见；首次打开会拉取应用列表。若列表为空/打不开，通常是设备到 iStoreOS 软件源的联网问题，与编译无关。

## 本轮新增：NPU 硬件加速 + HTTPS DNS 代理（DoH）

- **NPU / 硬件流卸载**：AN7581 内置 PPE（Packet Processor Engine）+ NPU（RISC-V）做硬件快转。内核驱动 `airoha_eth` 与 NPU 固件 `airoha-en7581-npu-firmware` 已显式钉进 `my.config`；另加 `kmod-nft-offload` 提供 nftables 流卸载路径。固件**首次启动即自动打开** `firewall` 的 `flow_offloading` 与 `flow_offloading_hw`（`diy-part2.sh` 写入的 uci-defaults 完成），无需手动开。
  - 验证：LuCI **状态 → 防火墙** 看 "Flow Offloading / Hardware Flow Offloading" 已勾选；或 `logread | grep -i ppe` / `nft list flowtables`。
- **NPU 状态监控页（肉眼确认加速）**：上游 `immortalwrt/luci` 没有 `luci-app-airoha-npu`，但社区仓库 [`luanmuc/luci-app-airoha-npu`](https://github.com/luanmuc/luci-app-airoha-npu)（v1.2.1，与你截图里那台"支持硬件加速"的固件**同源同版**）提供它。我们已把它**直接克隆进 `package/`**（`diy-part1.sh` 完成，仓库根即包本体），并钉入 `luci-app-airoha-npu` + `luci-i18n-airoha-npu-zh-cn`。
  - 它**只做监控/CPU 频率/PPE 流表展示**，**不负责开启硬件加速**（加速由上面的 NPU 固件 + `diy-part2.sh` 的 `flow_offloading_hw` 负责）——装这个页面纯粹是为了让你能在 LuCI 里**肉眼看见 NPU/PPE 在工作**。
  - LuCI 路径：**状态 → Airoha SoC Status (NPU, CPU, Frame Engine)**。可见 NPU 固件版本/负载、PPE 流表绑定数、各 GDM 端口 TX/RX 计数、CDM 硬件转发占比等。
  - 运行前提是 busybox 的 `devmem`（Frame Engine 寄存器访问 + CPU 超频用）。本版已在 `my.config` 设 `CONFIG_BUSYBOX_CUSTOM=y` + `CONFIG_BUSYBOX_CONFIG_DEVMEM=y` + `CONFIG_KERNEL_DEVMEM=y`，满足其 `devmem` 依赖。
  - 注意：该页面读取 `/sys/kernel/debug/ppe/entries` 等 debugfs，需内核开了 debugfs（OpenWrt 默认挂载），无需额外配置。

### 概览页的 CPU / PON 温度（状态 → 概览）

你参考固件里的 `温度: CPU: 60.5°C | PON: 46.3°C` 是 **LuCI 概览页（状态 → 概览）** 的一行。
**更正上一版说法**：它【不是】内核热区 `/sys/class/thermal/` 自动渲染，也不是 `luci-app-airoha-npu` 提供的。真实链路（均已核对上游源码）：

| 环节 | 位置 | 行为 |
|---|---|---|
| 前端 | `luci-mod-status/.../view/status/include/10_system.js` | `rpc luci.getTempInfo`，返回非空即插入「温度」行，**值原样显示** |
| 后端 | `luci-base/root/usr/share/rpcd/ucode/luci` | `getTempInfo: popen('/sbin/tempinfo')` |
| 数据源 | `/sbin/tempinfo` | 本编译由 `diy-part2.sh` 注入，拼装 CPU + PON 两个温度 |

- **CPU 温度**：`/sys/class/thermal/thermal_zone*/temp`（毫摄氏度 ÷ 1000）。`my.config` 已钉 `CONFIG_THERMAL=y` + `CONFIG_AIROHA_THERMAL=y`（Airoha EN7581 片上热传感器，内核 6.16+），保证热区存在。
- **PON 温度**：`/usr/sbin/ponctl ... status --json` → `frontend.temperature_celsius`，即**光模块 DDM 温度**，与「网络 → PON → 状态」页里的「光前端温度 41.47 °C」是同一个字段。依据 `pbs05/openwrt-pon-userspace` 的 `luci-app-pon/.../view/pon/status.js`（`fs.exec_direct('/usr/sbin/ponctl', ['--device', device, 'status', '--json'])` → `displayFrontendMetric(frontend, 'temperature_celsius', '°C')`）与 `airoha-ponctl/src/src/status.rs` 的 `convert_optics()`（`temperature_8472 ÷ 256`）。
  **它不在内核 thermal 子系统里，也不需要设备树注册 PON 热区**——所以上一版"等设备树暴露 PON 热区 / 本构建无解"的判断是错的，改由脚本直接读 ponctl 解决。
- **实现**：`diy-part2.sh` 写入 `files/usr/lib/pon-tempinfo/tempinfo` + `files/etc/uci-defaults/97-pon-tempinfo`（首启复制到 `/sbin/tempinfo`，避开构建系统 `files/` 与包安装的覆盖顺序不确定性）。依赖 `jsonfilter`（已在 `my.config` 显式钉入）解析 ponctl 的 JSON。
- **刷机后自测**：
  ```sh
  /sbin/tempinfo                 # 应输出 CPU: 59.1°C | PON: 41.5°C
  cat /sys/class/thermal/thermal_zone*/temp
  /usr/sbin/ponctl status --json | jsonfilter -e '@.frontend.temperature_celsius'
  ```
- 若只显示 CPU：说明 `ponctl status --json` 没返回 `frontend.temperature_celsius`（PON 未上线 / `--device` 参数不对）。脚本已自动尝试 `uci get pon.@xpon[0].device` 作为 `--device`，仍失败时把 `tempinfo` 里的 ponctl 调用改成与 `luci-app-pon` 状态页一致的参数即可。
- **HTTPS DNS 代理（DoH）**：集成 `https-dns-proxy` + `luci-app-https-dns-proxy`。默认用 Google/Cloudflare 的 DoH，并自动接管 dnsmasq 的上游，实现 DNS 加密防劫持。LuCI 路径：**服务 → HTTPS DNS Proxy**。依赖的 `ca-bundle` 已在本文件上方的"在线安装能力"段配置。
  - 想换 DoH 提供商（如 AdGuard、Quad9、阿里/腾讯）：在 **服务 → HTTPS DNS Proxy** 里改 `resolver_url` 即可。

本次 `my.config` 关键符号：`airoha-en7581-npu-firmware`、`kmod-nft-offload`、`luci-app-airoha-npu`、`luci-i18n-airoha-npu-zh-cn`、`https-dns-proxy`、`luci-app-https-dns-proxy`、`CONFIG_THERMAL` / `CONFIG_AIROHA_THERMAL`（CPU 热区，显式声明/冗余保护）、`jsonfilter`（tempinfo 解析 ponctl JSON）、`luci-app-store`（iStore，软失败）、`luci-app-openvpn` + `luci-i18n-openvpn-zh-cn`（OpenVPN 客户端）、`CONFIG_FEED_{pon_drivers,pon_userspace,istore,video}=m`（软件源编译期修复），以及 9 条 DDNS `is not set`。

> 温度部分本轮**未改动**：`diy-part2.sh` 的 `tempinfo` / `97-pon-tempinfo` 与 `my.config` 的 `CONFIG_THERMAL` / `CONFIG_AIROHA_THERMAL` / `jsonfilter` 保持不变；`build.yml` 在 Load custom feeds 步骤硬校验 4 个自定义文件、在配置阶段硬断言 `jsonfilter`。刷机后 `/sbin/tempinfo` 应输出 `CPU: 59.1°C | PON: 41.5°C`。

## 想让我以后直接帮你触发编译？

当前对话没有你的 GitHub 凭据，我无法自动 push / 触发 Actions。两种方式可开放给我：
- 在本机装好 `gh` 并 `gh auth login`（或配 PAT），把仓库交给我；
- 或在 WorkBuddy 里连接 GitHub 连接器。
连上后，我可以帮你 git push 并 `gh workflow run` 启动，再把结果回传给你。
