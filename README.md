<h1 align="center">Codex-Notifier</h1>

<p align="center">
  <a href="#"><img alt="Version" src="https://img.shields.io/badge/version-v0.2.2-blue.svg" /></a>
  <a href="#"><img alt="VS Code" src="https://img.shields.io/badge/VS%20Code-extension-007ACC.svg" /></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green.svg" /></a>
  &nbsp;&nbsp;
  <a href="README-zh.md">中文说明</a>
</p>

✅ **Get notified immediately when Codex tasks finish | Native desktop toast popup | Native notification sound**  
✅ **Click to jump back to the related Codex window | Supports VS Code Codex extension and CLI | Multi-window Codex parallel sessions | Supports all Codex versions**  
✅ **One-line prompt for automated install and verification | Windows | Simple hooks pipeline**

Codex-Notifier turns Codex task completion into reliable desktop feedback on Windows.  
It keeps your existing Codex flow intact while adding predictable notifications and click-to-focus behavior.

## Visual Demo

<p align="center">
  <img src="docs/demo/image.png" alt="Codex-Notifier demo" width="760" />
</p>

## Features  

| Feature | Description |
| :--- | :--- |
| **🔔 Hook-based Notification** | Uses `hooks.Stop` to trigger completion notifications without MCP or skill runtime dependencies. |
| **🖱 Click-to-Jump VSCode** | Clicking the balloon focuses the matching VSCode workspace window first; falls back to `code -r <cwd>`. |
| **🧩 Safe Config Merge** | Installer merges `~/.codex/config.toml` with managed markers and conflict detection (`exit 20`). |
| **🧪 Operational Scripts** | Includes `install`, `doctor`, and `uninstall` scripts for setup, validation, and rollback. |
| **🌐 i18n/l10n Scaffold** | Supports `en-US` + `zh-CN`, CLDR formatting, ICU plural templates, and pseudo RTL (`ar-XB`) validation. |

## Install Prompt (Send to Codex)

`Please install Codex-Notifier on Windows: clone https://github.com/MaxMiksa/Codex-Notifier, run scripts/install.ps1; if a Stop hook conflict appears, merge ~/.codex/config.toml using templates/stop-hook.snippet.toml while keeping existing hooks; then run scripts/doctor.ps1 and report back.`

<details>
  <summary>(Optional) Manual install and verification</summary>

1. Run the installer in the repository directory:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```
2. Ask Codex to execute a minimal task, for example:
```powershell
codex exec "say hi"
```
3. When completion notification appears, click the balloon to jump back to the matching VSCode window.

</details>

<details>
  <summary>Requirements & Limits</summary>

- Windows + PowerShell (`pwsh.exe`) required.
- Codex CLI and VSCode are expected to be installed.
- v0.2.2 targets Windows only.
- Balloon click callback works within the active notification window, not guaranteed from historical Action Center entries.

</details>

<details>
  <summary>Compliance (Global Minimal)</summary>

- Privacy notice: notifications are generated only from local runtime events.
- Local processing: payload parsing and window matching are performed on-device.
- No upload: Codex-Notifier does not forward payload content to external services.
- Audit log: runtime metadata is recorded in local JSONL logs.

</details>

<details>
  <summary>Developer Guide</summary>

- Install to real Codex home:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -CodexHome "$HOME\.codex"
```
- Force locale/legal profile:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Locale "zh-CN" -LegalProfile "global-minimal"
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
  <summary>Troubleshooting</summary>

- If install returns `conflict_manual_merge_required` (`exit 20`), merge the stop hook snippet manually.
- If click jump does not hit expected workspace, verify window title contains `- <workspace> - Visual Studio Code`.
- Runtime logs are written to `~/.codex/hooks/logs/notify-stop-events.jsonl`.

</details>

## 🤝 Contribution & Contact

Welcome to submit Issues and Pull Requests!
Any questions or suggestions? Please contact Zheyuan (Max) Kong (Carnegie Mellon University, Pittsburgh, PA).

Zheyuan (Max) Kong: kongzheyuan@outlook.com | zheyuank@andrew.cmu.edu

