<h1 align="center">Codex-Notifier</h1>

<p align="center">
  <a href="#"><img alt="版本" src="https://img.shields.io/badge/版本-v0.2.4-blue.svg" /></a>
  <a href="#"><img alt="VS Code" src="https://img.shields.io/badge/VS%20Code-扩展-007ACC.svg" /></a>
  <a href="LICENSE"><img alt="许可证" src="https://img.shields.io/badge/许可证-MIT-green.svg" /></a>
  &nbsp;&nbsp;
  <a href="README.md"><img alt="[English]" src="https://img.shields.io/badge/%5BEnglish%5D-2f3640.svg" /></a>
</p>

✅ **Codex任务完成后立刻通知你 | 原生桌面级消息弹窗 | 原生消息提示音**  
✅ **支持点击跳转到对应 VS Code 窗口 | 支持多窗口 Codex 并行 | 支持所有 Codex 版本**  
✅ **一句 Prompt 自动安装与校验 | Windows | VS Code Codex 插件 | 简单 Hooks 链路**

Codex-Notifier 让 Codex 在任务完成时主动提醒你（通过弹窗和声音）。  
它不改变你的 Codex 工作流。

## 🎬 演示

<p align="center">
  <img src="docs/demo/image.png" alt="Codex-Notifier 演示（英文）" width=600 />
  <img src="docs/demo/image-zh.png" alt="Codex-Notifier 演示（中文）" width=600 />
</p>

## ✨ 功能

| 功能 | 说明 |
| :--- | :--- |
| **基于 Hook 的通知** | Codex 任务一结束，就会弹出桌面通知并播放提示音。 |
| **客户端范围控制** | 仅在 Codex CLI 与 VS Code 扩展会话中触发；Codex Desktop 会话默认不提醒。 |
| **点击跳转 VSCode** | 点击通知即可回到对应的 VS Code 窗口。 |
| **安全配置合并** | 安装时会尽量保留你原有配置，只补充本工具需要的内容。 |
| **运维脚本齐全** | 自带安装、体检、卸载脚本，按步骤执行即可。 |
| **支持中英双语** | 提供中文与英文文档及安装 Prompt，便于不同语言用户快速上手。 |
| **i18n/l10n 脚手架** | 从一开始就按多语言方式组织，后续扩展语言更轻松。 |


## 🚀 安装 Prompt （发给Codex即可）

```text
请在 Windows 上帮我安装 Codex-Notifier：克隆 https://github.com/MaxMiksa/Codex-Notifier，执行 scripts/install.ps1；若提示 Stop 冲突，按 templates/stop-hook.snippet.toml 合并 ~/.codex/config.toml（保留原有 hooks）；再执行 scripts/doctor.ps1 并汇报。
```

<details>
  <summary>（可选）手动安装和测试方式</summary>

1. 在仓库目录执行安装：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```
2. 让 Codex 执行一个最小任务，例如：
```powershell
codex exec "say hi"
```
3. 出现完成通知后点击气泡，即可跳转回对应 VSCode 窗口。

</details>

## 📚 更多

<details>
  <summary>环境要求与限制</summary>

- 需要 Windows + PowerShell (`pwsh.exe`)。
- 默认假设已安装 Codex CLI 与 VSCode。
- v0.2.4 当前仅支持 Windows。
- 通知当前仅面向 Codex CLI 与 VS Code 扩展会话；Codex Desktop 会话会被有意跳过。
- 气泡点击回调仅保证在通知展示窗口内有效，系统通知中心历史项不保证可回调。

</details>

<details>
  <summary>合规说明（Global Minimal）</summary>

- 隐私说明：通知仅基于本地运行事件生成。  
- 本地处理：payload 解析与窗口匹配均在设备本地完成。  
- 不上传数据：Codex-Notifier 不会向外部服务转发 payload 内容。  
- 审计日志：运行元数据记录在本地 JSONL 日志中。  

</details>

<details>
  <summary>开发者指南</summary>

- 安装到真实 Codex 主目录：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -CodexHome "$HOME\.codex"
```
- 指定语言与合规档：
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Locale "zh-CN" -LegalProfile "global-minimal"
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
  <summary>故障排查</summary>

- 若安装返回 `conflict_manual_merge_required`（`exit 20`），请按模板手动合并 Stop Hook。
- 若点击未跳到目标窗口，先确认窗口标题包含 `- <workspace> - Visual Studio Code`。
- 运行日志位于 `~/.codex/hooks/logs/notify-stop-events.jsonl`。

</details>

## 🤝 贡献与联系

欢迎提交 Issue 和 Pull Request！  
如有任何问题或建议，请联系 Zheyuan (Max) Kong (卡内基梅隆大学，宾夕法尼亚州)。

Zheyuan (Max) Kong: kongzheyuan@outlook.com | zheyuank@tepper.cmu.edu
本项目 GitHub 链接：https://github.com/MaxMiksa/Codex-Notifier
