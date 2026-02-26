# Codex-Notifier i18n UI Guidelines

## Principles
- Use locale keys for all user-facing text; never hard-code UI strings in runtime scripts or UI scaffolds.
- Use logical CSS properties (`margin-inline`, `padding-inline`, `inset-inline`) instead of physical left/right values.
- Use locale-aware formatting for time, numbers, and currency via CLDR-compatible APIs.

## Fluid Layout Rules
- Keep containers responsive with `max-width` + `width: min(100%, ...)`.
- Allow text wrapping with `overflow-wrap: anywhere` for long localized strings.
- Avoid fixed widths for labels/buttons; prefer intrinsic sizing and `gap`.
- Truncate only as a last resort, and use grapheme-safe truncation.

## RTL Readiness
- Drive direction using a single source (`dir` attribute or resolved direction state).
- Never mirror text manually; rely on direction-aware layout and logical properties.
- Keep icon placement direction-aware (`margin-inline-start/end`), not `margin-left/right`.
- Validate with pseudo-RTL locale (`ar-XB`) before introducing production RTL language packs.

## l10n Compliance Fields (Global Minimal)
- `legal.privacy_notice`
- `legal.local_processing_notice`
- `legal.no_upload_notice`
- `legal.audit_log_notice`

These fields should be localized and surfaced consistently in diagnostics or compliance summaries.

## Verification Checklist
1. Locale toggle updates all visible text.
2. `dir=rtl` layout does not overflow or overlap.
3. Long translated strings remain readable and wrapped.
4. Time/number formats differ correctly between `en-US` and `zh-CN`.
5. No UI string literals remain in hooks/scripts (run `scripts/check-i18n-hardcode.ps1`).
