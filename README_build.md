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

日志里会出现这三组关键行（任意一组缺失/报错即失败）：

- `设备符号 ... 未生效` → **不能**出现（出现说明回落 EVB）
- `PON 组件未生效` → **不能**出现（出现说明 PON feeds 没装上）
- `PON 校验通过：固件内已含 airoha-pond / kmod-airoha-xpon 等` → **必须**出现

可选功能解析情况里：
- `[ OK ] luci-app-store` → iStore 已编进固件
- `[MISS] luci-app-store` → iStore 因依赖/兼容问题被静默丢弃（见下方说明）

## 产物位置

- `bin/targets/airoha/an7581/` 下的 `*-nokia_xg-040g-md-ubi-sysupgrade.itb` 即为固件。
- 若开了 `UPLOAD_RELEASE=true`，会在 Release 里下载。

## 刷机与 PON 上线（与编译无关但必须做）

1. 用 [AN758x-Stock2UBI](https://github.com/pbs05/an758x-stock2ubi) 备份原厂并刷入 UBI 布局，U-Boot 用 [AN758x U-Boot](https://github.com/pbs05/uboot-an758x)。
2. 刷完 PonWrt 后，在 LuCI **网络 → PON → 配置 → PON board data** 恢复诺基亚的 `bosa`、`ri` 两个卷（来自原厂备份），否则 PON 口不会注册上线。

## 关于 iStore 的兼容性说明

PonWrt 这棵源码基于 ImmortalWrt master、默认用 **apk** 包管理器。iStore 官方已支持 apk，但其 `quickstart`/`luci-app-store` 在某些组合下可能依赖缺失而**被 defconfig 静默丢弃**（表现为 `[MISS] luci-app-store`，不会让编译失败）。若你发现 iStore 没出来：

- 进入仓库后看编译日志的 `[MISS]` 行；
- 若确认 iStore 拖垮了 `feeds install -a`（整步失败），把 `feeds.conf.default` 里 `src-git istore ...` 那行注释掉，并删掉 `my.config` 末尾的 `luci-app-store` / `luci-app-filebrowser` 两行即可，PON 与其它功能不受影响。

## 想让我以后直接帮你触发编译？

当前对话没有你的 GitHub 凭据，我无法自动 push / 触发 Actions。两种方式可开放给我：
- 在本机装好 `gh` 并 `gh auth login`（或配 PAT），把仓库交给我；
- 或在 WorkBuddy 里连接 GitHub 连接器。
连上后，我可以帮你 git push 并 `gh workflow run` 启动，再把结果回传给你。
