## v0.1.0 – Initial Distributable Release (2026-02-26)

### Feature 1: Hook-based completion notification pipeline
- **Summary**: Added `notify-stop.ps1` to convert Codex completion events into desktop notification triggers.
- **Problem Solved**: Notification behavior previously lived only in local `~/.codex` state and was not portable.
- **Feature Details**: The script handles payload-tolerant parsing, rule-based summary text, same-thread cooldown dedup, and normalized JSONL logging.
- **Technical Implementation**: 
  - Added `hooks/notify-stop.ps1` as the `hooks.Stop` entrypoint.
  - Implemented hard-marker-first decision path with fallback rules and guaranteed `exit 0`.
  - Extended structured event logs for operational observability.

### Feature 2: Click-to-focus VSCode workspace behavior
- **Summary**: Added `notify-click-jump.ps1` to activate the relevant VSCode window when notification is clicked.
- **Problem Solved**: Users had to manually switch windows after completion, especially in parallel Codex sessions.
- **Feature Details**: Notification style and sound are preserved; click handling prefers workspace-title window matching and falls back to `code -r`.
- **Technical Implementation**: 
  - Added Win32 integration via `EnumWindows` and `SetForegroundWindow`.
  - Registered both `BalloonTipClicked` and `Click` handlers.
  - Logged jump outcomes using `window-title`, `window-any`, and `code-reuse-window` strategies.

### Feature 3: Repository packaging and installer toolchain
- **Summary**: Added install/doctor/uninstall scripts and templates for one-prompt installation.
- **Problem Solved**: Existing setup was not distributable because active assets were outside repository control.
- **Feature Details**: Installer backs up and merges `~/.codex/config.toml`, returns `20` on Stop-hook conflicts, and is idempotent for re-runs.
- **Technical Implementation**: 
  - Added `scripts/install.ps1`, `scripts/doctor.ps1`, `scripts/uninstall.ps1`.
  - Added `scripts/lib/config-merge.ps1` for managed block merge and conflict detection.
  - Added `templates/stop-hook.snippet.toml` plus bilingual README onboarding docs.
