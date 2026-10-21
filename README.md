# DualWeb — JDCloud RE-SS-01 AX1800 Pro

本仓库面向 **京东云 RE-SS-01（亚瑟 / AX1800 Pro）**，目标为 OpenWrt `qualcommax/ipq60xx`，设备配置 `jdcloud_re-ss-01`。设备为 Qualcomm IPQ6000、512 MiB RAM、eMMC 存储；请勿使用 R619AC 的 NAND 镜像。

## 构建方式

1. 打开 GitHub Actions → **Build JDCloud RE-SS-01 DualWeb (OpenWrt)**。
2. 点击 **Run workflow**，默认使用 OpenWrt Snapshot ImageBuilder。
3. 构建会从 `wfzc6880530/dualweb` 的 `test/2026-10-21-functional-b-scheme` 分支获取 DualWeb 页面、API 和 overlay，再集成适用于 ARM64 的插件与 Open-Box。
4. 构建成功后，在 Actions 对应运行记录的 Artifacts 下载固件与 SHA256 校验文件。

仓库使用 ImageBuilder，而不是从头编译整个 OpenWrt SDK。构建脚本会验证设备 profile、第三方 APK 校验和、ARM64 Mihomo 核心架构，以及 80 端口 Open-Box/Zashboard 静态资源。插件依赖若与当前 Snapshot 不兼容，构建会在 manifest 阶段失败，不会把缺少插件的镜像当成完整成功版本。

## 集成范围

- **80 端口 DualWeb：** WAN DHCP/PPPoE/静态 IP、带回滚的网络设置、首页密码、连通性测试。
- **8080 端口 LuCI：** 保留完整 LuCI，预设 Vantage 主题。
- **OpenClash：** 预装 OpenClash LuCI APK 与 ARM64 Mihomo Meta 核心。
- **PassWall：** 加入 PassWall 与简体中文语言包。
- **NPS/NPC：** 加入 nps、npc 和 LuCI 管理包。
- **Vantage：** 固定版本 APK 并验证 SHA256，校验失败时终止构建。
- **Open-Box：** 官方 ARM64 bundle；原版管理服务保持在 3036。80 端口采用独立副本，仅显示“概览 / 代理 / 规则”，API 通过同源 Nginx 反代，避免修改原版 3036 前端。
- **Zashboard：** 作为 80 端口独立静态页面集成，代理 API 反代至本机 9090。
- **其他：** ttyd、LuCI 在线升级辅助、vlmcsd。

Open-Box 上游许可证可能限制运行时再分发。公开固件前请确认所选版本的许可和再分发权限；本构建从官方 Release 下载。

## 固件类型和刷机警告

- `*-jdcloud_re-ss-01-squashfs-sysupgrade.bin`：用于设备已运行兼容 OpenWrt 时的 sysupgrade。
- 上游 Snapshot ImageBuilder 可能只生成 sysupgrade 镜像，不保证提供 `initramfs-uImage.itb`；initramfs 是可选产物。
- 本仓库不生成可直接用于原厂固件首次刷机的专用镜像。不要假定原厂 Web 页面可直接接受 sysupgrade 镜像。

## 重要说明

插件包依赖 Snapshot 的实时 feed；上游包索引或 ABI 变化可能导致构建失败，需要根据 manifest 日志调整包源或版本。构建成功不等于已完成真实硬件上的无线、网口、eMMC、重启、升级和恢复验证。
