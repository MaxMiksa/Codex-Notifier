<h1 align="center">Codex-Notifier</h1>

<p align="center">
  <a href="#"><img alt="Version" src="https://img.shields.io/badge/version-v0.2.0-blue.svg" /></a>
  <a href="#"><img alt="VS Code" src="https://img.shields.io/badge/VS%20Code-extension-007ACC.svg" /></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green.svg" /></a>
  &nbsp;&nbsp;
  <a href="README-zh.md">中文说明</a>
</p>

✅ **Hook-only architecture | Local notifications | Click-to-jump VSCode workspace | Works with multi-window Codex sessions**  
✅ **Task completion popup | Soft sound prompt | Notification dedup and fallback routing**  
✅ **Windows + PowerShell | Codex CLI hooks | VSCode workspace title matching**

Codex-Notifier turns Codex task completion into reliable desktop feedback on Windows.  
It keeps your existing Codex flow intact while adding predictable notifications and click-to-focus behavior.

## Visual Demo

<p align="center">
  <img src="Presentation/demo.gif" alt="Codex-Notifier demo" width="760" />
</p>

## Features

| Feature | Description |
| :--- | :--- |
| **🔔 Hook-based Notification** | Uses `hooks.Stop` to trigger completion notifications without MCP or skill runtime dependencies. |
| **🖱 Click-to-Jump VSCode** | Clicking the balloon focuses the matching VSCode workspace window first; falls back to `code -r <cwd>`. |
| **🧩 Safe Config Merge** | Installer merges `~/.codex/config.toml` with managed markers and conflict detection (`exit 20`). |
| **🧪 Operational Scripts** | Includes `install`, `doctor`, and `uninstall` scripts for setup, validation, and rollback. |
| **🌐 i18n/l10n Scaffold** | Supports `en-US` + `zh-CN`, CLDR formatting, ICU plural templates, and pseudo RTL (`ar-XB`) validation. |

## Compliance (Global Minimal)

- Privacy notice: notifications are generated from local runtime events.
- Local processing: payload parsing and window matching run on-device.
- No upload: Codex-Notifier does not forward payload content to external services.
- Audit log: operational metadata is stored in local JSONL logs.

## Usage (Happy Path)

1. Open a terminal in this repo and run:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```
2. Ask Codex to run any small task, for example:
```powershell
codex exec "say hi"
```
3. When completion notification appears, click it to jump back to the related VSCode window.

## One-line AI Install Prompt

`Please install Codex-Notifier on Windows: clone https://github.com/MaxMiksa/Codex-Notifier, run scripts/install.ps1; if Stop hook conflict appears, merge ~/.codex/config.toml using templates/stop-hook.snippet.toml while keeping existing hooks; then run scripts/doctor.ps1 and report.`

<details>
  <summary>Requirements & Limits</summary>

- Windows + PowerShell (`pwsh.exe`) required.
- Codex CLI and VSCode are expected to be installed.
- v0.2.0 targets Windows only.
- Balloon click callback works within the active notification window, not guaranteed from historical Action Center entries.

</details>

<details>
  <summary>Developer Guide</summary>

- Install to real Codex home:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -CodexHome "$HOME\.codex"
```
- Force locale/legal profile:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Locale "en-US" -LegalProfile "global-minimal"
```
- Validate installation:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -RunSmokeTest
```
- Uninstall managed hook artifacts:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

</details>

<details>
  <summary>Troubleshooting / Known Issues</summary>

- If install returns `conflict_manual_merge_required` (`exit 20`), merge the stop hook snippet manually.
- If click jump does not hit expected workspace, verify window title contains `- <workspace> - Visual Studio Code`.
- Runtime logs are written to `~/.codex/hooks/logs/notify-stop-events.jsonl`.

</details>

## 🤝 Contribution & Contact

Welcome to submit Issues and Pull Requests!
Any questions or suggestions? Please contact Zheyuan (Max) Kong (Carnegie Mellon University, Pittsburgh, PA).

Zheyuan (Max) Kong: kongzheyuan@outlook.com | zheyuank@andrew.cmu.edu
