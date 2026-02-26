<h1 align="center">Codex-Notifier</h1>

<p align="center">
  <a href="#"><img alt="版本" src="https://img.shields.io/badge/版本-v0.1.0-blue.svg" /></a>
  <a href="#"><img alt="VS Code" src="https://img.shields.io/badge/VS%20Code-扩展-007ACC.svg" /></a>
  <a href="LICENSE"><img alt="许可证" src="https://img.shields.io/badge/许可证-MIT-green.svg" /></a>
  &nbsp;&nbsp;
  <a href="README.md">English</a>
</p>

✅ **纯 Hooks 链路 | 本地桌面通知 | 点击跳转 VSCode 工作区 | 支持多窗口 Codex 并行**  
✅ **任务完成弹窗 | 柔和提示音 | 去重过滤与兜底跳转**  
✅ **Windows + PowerShell | Codex CLI hooks | 基于窗口标题匹配工作区**

Codex-Notifier 用于把 Codex 的任务完成状态稳定地变成桌面反馈。  
它不改变你的 Codex 工作流，只增加可靠提醒和点击回焦能力。

## 可视化演示

<p align="center">
  <img src="Presentation/demo.gif" alt="Codex-Notifier 演示" width="760" />
</p>

## 功能特性

| 功能 | 说明 |
| :--- | :--- |
| **🔔 基于 Hook 的通知** | 使用 `hooks.Stop` 触发完成通知，不依赖 MCP 或 Skills 运行链路。 |
| **🖱 点击跳转 VSCode** | 点击气泡优先激活匹配工作区窗口，失败时回退 `code -r <cwd>`。 |
| **🧩 安全配置合并** | 安装器以受管标记合并 `~/.codex/config.toml`，冲突时返回 `exit 20`。 |
| **🧪 运维脚本齐全** | 提供 `install`、`doctor`、`uninstall` 三件套，覆盖安装、校验与回滚。 |

## 使用方式（推荐路径）

1. 在仓库目录执行安装：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```
2. 让 Codex 执行一个最小任务，例如：
```powershell
codex exec "say hi"
```
3. 出现完成通知后点击气泡，即可跳转回对应 VSCode 窗口。

## 一句 Prompt 安装

`请在 Windows 上帮我安装 Codex-Notifier：克隆 https://github.com/MaxMiksa/Codex-Notifier，执行 scripts/install.ps1；若提示 Stop 冲突，按 templates/stop-hook.snippet.toml 合并 ~/.codex/config.toml（保留原有 hooks）；再执行 scripts/doctor.ps1 并汇报。`

<details>
  <summary>环境要求与限制</summary>

- 需要 Windows + PowerShell (`pwsh.exe`)。
- 默认假设已安装 Codex CLI 与 VSCode。
- v0.1.0 当前仅支持 Windows。
- 气泡点击回调仅保证在通知展示窗口内有效，系统通知中心历史项不保证可回调。

</details>

<details>
  <summary>开发者指南</summary>

- 安装到真实 Codex 主目录：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -CodexHome "$HOME\.codex"
```
- 安装后自检：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -RunSmokeTest
```
- 卸载受管 Hook：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

</details>

<details>
  <summary>故障排查 / 已知问题</summary>

- 若安装返回 `conflict_manual_merge_required`（`exit 20`），请按模板手动合并 Stop Hook。
- 若点击未跳到目标窗口，先确认窗口标题包含 `- <workspace> - Visual Studio Code`。
- 运行日志位于 `~/.codex/hooks/logs/notify-stop-events.jsonl`。

</details>

## 🤝 贡献与联系

欢迎提交 Issue 和 Pull Request！  
如有任何问题或建议，请联系 Zheyuan (Max) Kong (卡内基梅隆大学，宾夕法尼亚州)。

Zheyuan (Max) Kong: kongzheyuan@outlook.com | zheyuank@andrew.cmu.edu
