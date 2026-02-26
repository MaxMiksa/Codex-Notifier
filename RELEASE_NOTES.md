## v0.1.0 – Initial Public Setup / 首个公开可安装版本 (2026-02-26)

## ✨ Codex 通知能力正式仓库化

**本次发布将本地散落脚本收敛为可分发仓库，支持“一句 Prompt 安装”、点击通知跳转工作区，以及可观测的日志链路。**

| 类别 | 详细内容 |
| :--- | :--- |
| **通知主链路** | 基于 `hooks.Stop` 的完成提醒，支持规则过滤和去重。 |
| **点击跳转** | 点击气泡优先激活匹配 VSCode 窗口，失败自动回退 `code -r`。 |
| **安装体验** | 提供 `install/doctor/uninstall`，支持备份、幂等安装和冲突返回码 `20`。 |
| **文档交付** | 提供双语 README 与安装 Prompt，便于用户让自己的 Codex 自动安装。 |

## ✨ First Public, Prompt-installable Codex Notifier

**This release packages local-only scripts into a distributable repository with one-prompt install flow, clickable workspace jump, and structured runtime observability.**

| Category | Details |
| :--- | :--- |
| **Notification Pipeline** | Completion reminders are triggered from `hooks.Stop` with filtering and dedup safeguards. |
| **Click Jump** | Notification click focuses the matching VSCode workspace window, then falls back to `code -r`. |
| **Installer UX** | Includes `install/doctor/uninstall` with config backup, idempotent re-run support, and conflict exit code `20`. |
| **Docs Delivery** | Ships bilingual README and install prompt for Codex-driven setup. |
