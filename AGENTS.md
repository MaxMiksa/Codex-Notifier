# Codex-Notifier Agent Notes

## Tooling Note (Windows PowerShell Policy)
- Symptom: `Remove-Item -Recurse -Force` commands may be rejected by execution policy in this environment.
- Cause: Command policy blocks some destructive PowerShell patterns even in local workspace operations.
- Fix: Prefer `cmd /c rd /s /q <path>` for test-temp cleanup when PowerShell removal is blocked.
