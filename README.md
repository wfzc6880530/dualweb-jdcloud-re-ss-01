# DualWeb — JDCloud RE-SS-01 AX1800 Pro

本仓库面向 **京东云 RE-SS-01（亚瑟 / AX1800 Pro）**，目标为 OpenWrt `qualcommax/ipq60xx`，设备配置 `jdcloud_re-ss-01`。设备为 Qualcomm IPQ6000、512 MiB RAM、eMMC 存储；请勿使用 R619AC 的 NAND 镜像。

## 构建方式

1. 打开 GitHub Actions → **Build JDCloud RE-SS-01**。
2. 点击 **Run workflow**。
3. 首次构建会从 `wfzc6880530/dualweb` 的 `test/openbox-artifacts` 分支取 DualWeb 前端、API 和 overlay，再使用 OpenWrt snapshot ImageBuilder 生成设备镜像。
4. 构建成功后，在 Actions 对应运行记录的 Artifacts 下载固件与 SHA256 校验文件。

仓库当前采用 ImageBuilder，而不是从头编译整个 OpenWrt SDK。设备支持来自上游；构建时会验证 ImageBuilder 的设备 profile 是否存在。若上游版本、包索引或某个依赖发生变化，构建会明确失败，不应将不完整产物用于刷机。

## 固件类型和刷机警告

- `*-jdcloud_re-ss-01-initramfs-uImage.itb`：用于设备支持的临时启动/首次安装流程；不是常规升级镜像。
- `*-jdcloud_re-ss-01-squashfs-sysupgrade.bin`：仅在设备已运行兼容的 OpenWrt/ImmortalWrt 时用于 sysupgrade。
- 首次刷机可能需要 U-Boot/TFTP；请严格按设备对应的官方说明操作，并提前准备恢复方案。
- 不要在刷机前假定 OEM 原厂 Web 管理页面可直接接受 sysupgrade 镜像。

## DualWeb 首页

首页端口 80，LuCI 管理端口 8080。首次启动的首页密码沿用上游默认值 `root`，登录后请立即修改。首次启动时 DualWeb 的独立服务会尝试从 Nikki 官方安装源安装 Nikki/Mihomo；网络或上游源不可用时，代理控制功能可能暂时不可用。

## Open-Box

此仓库不会把 Open-Box 专有运行时自动打入公开固件。只有在确认所选版本许可证允许再分发后，才应考虑公开集成。

## 免责声明

固件尚需在真实硬件上验证无线、以太网、eMMC、重启、升级和恢复流程。Actions 构建成功不等于已完成硬件验证。