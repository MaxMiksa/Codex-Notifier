[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $HOME '.codex'),
  [string]$DefaultCwd = '',
  [string]$Locale = 'auto',
  [string]$LegalProfile = 'global-minimal',
  [switch]$RunSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\locale-resolver.ps1')
. (Join-Path $PSScriptRoot 'lib\layout-direction.ps1')
. (Join-Path $PSScriptRoot 'lib\i18n-core.ps1')

function Resolve-EffectiveDefaultCwd {
  param([string]$Configured)

  if (-not [string]::IsNullOrWhiteSpace($Configured) -and (Test-Path -LiteralPath $Configured)) {
    return $Configured
  }

  $desktopPath = Join-Path $HOME 'Desktop'
  $defaultPath = Join-Path $desktopPath 'default'
  if (Test-Path -LiteralPath $defaultPath) {
    return $defaultPath
  }
  if (Test-Path -LiteralPath $desktopPath) {
    return $desktopPath
  }
  return $HOME
}

function Invoke-StopHookSmokeTest {
  param(
    [Parameter(Mandatory = $true)][string]$StopHookPath,
    [Parameter(Mandatory = $true)][string]$EffectiveDefaultCwd,
    [Parameter(Mandatory = $true)][string]$LocaleEffective,
    [Parameter(Mandatory = $true)][string]$DirEffective,
    [Parameter(Mandatory = $true)][string]$LegalProfileEffective
  )

  $payload = '{"type":"smoketest","event":"smoketest","thread-id":"doctor-smoketest","turn-id":"doctor-smoketest"}'
  $payload | & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $StopHookPath -DefaultCwd $EffectiveDefaultCwd -Locale $LocaleEffective -Dir $DirEffective -LegalProfile $LegalProfileEffective
  return $LASTEXITCODE
}

function Emit-ResultAndExit {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Result,
    [int]$ExitCode = 0
  )

  $json = $Result | ConvertTo-Json -Depth 8 -Compress
  Write-Output $json
  exit $ExitCode
}

try {
  $localeInfo = Resolve-NotifierLocale -Locale $Locale
  $dirInfo = Resolve-NotifierDirection -Dir 'auto' -Locale $localeInfo.locale
  $legalInfo = Resolve-NotifierLegalProfile -LegalProfile $LegalProfile
  $effectiveLocale = [string]$localeInfo.locale
  $effectiveDir = [string]$dirInfo.dir_effective
  $effectiveLegalProfile = [string]$legalInfo.legal_profile

  $effectiveDefaultCwd = Resolve-EffectiveDefaultCwd -Configured $DefaultCwd
  $hooksDir = Join-Path $CodexHome 'hooks'
  $logsPath = Join-Path $hooksDir 'logs\notify-stop-events.jsonl'
  $stopHookPath = Join-Path $hooksDir 'notify-stop.ps1'
  $clickHookPath = Join-Path $hooksDir 'notify-click-jump.ps1'
  $configPath = Join-Path $CodexHome 'config.toml'
  $localeDir = Join-Path $CodexHome 'i18n\locales'

  $checks = [ordered]@{
    stop_hook_exists = (Test-Path -LiteralPath $stopHookPath)
    click_hook_exists = (Test-Path -LiteralPath $clickHookPath)
    config_exists = (Test-Path -LiteralPath $configPath)
    locale_dir_exists = (Test-Path -LiteralPath $localeDir)
    managed_block_present = $false
    stop_entry_present = $false
    log_path_exists = (Test-Path -LiteralPath $logsPath)
    smoke_test_ok = $null
  }

  if ($checks.config_exists) {
    $configText = Get-Content -LiteralPath $configPath -Raw
    $checks.managed_block_present = (
      $configText -match '(?m)^\s*# codex-notifier managed block start\s*$' -and
      $configText -match '(?m)^\s*# codex-notifier managed block end\s*$'
    )
    $checks.stop_entry_present = ($configText -match '(?m)^\s*Stop\s*=')
  }

  if ($RunSmokeTest.IsPresent -and $checks.stop_hook_exists) {
    $checks.smoke_test_ok = ((Invoke-StopHookSmokeTest `
          -StopHookPath $stopHookPath `
          -EffectiveDefaultCwd $effectiveDefaultCwd `
          -LocaleEffective $effectiveLocale `
          -DirEffective $effectiveDir `
          -LegalProfileEffective $effectiveLegalProfile) -eq 0)
  }

  $failed = @()
  foreach ($item in @('stop_hook_exists', 'click_hook_exists', 'config_exists', 'managed_block_present', 'stop_entry_present', 'locale_dir_exists')) {
    if (-not [bool]$checks[$item]) {
      $failed += $item
    }
  }
  if ($RunSmokeTest.IsPresent -and -not [bool]$checks.smoke_test_ok) {
    $failed += 'smoke_test_ok'
  }

  $notices = Get-I18nLegalNotices -Locale $effectiveLocale
  $complianceSummary = Get-I18nText -Key 'doctor.compliance_summary' -Locale $effectiveLocale -ArgsObject @{
    privacy = $notices.privacy
    localProcessing = $notices.localProcessing
    noUpload = $notices.noUpload
    audit = $notices.audit
  }

  $status = if ($failed.Count -eq 0) { 'ok' } else { 'failed' }
  Emit-ResultAndExit -Result @{
    status = $status
    codex_home = $CodexHome
    effective_default_cwd = $effectiveDefaultCwd
    hooks_dir = $hooksDir
    log_path = $logsPath
    checks = $checks
    failed_checks = $failed
    locale_effective = $effectiveLocale
    dir_effective = $effectiveDir
    legal_profile = $effectiveLegalProfile
    compliance_summary = $complianceSummary
  } -ExitCode ($(if ($status -eq 'ok') { 0 } else { 1 }))
} catch {
  Emit-ResultAndExit -Result @{
    status = 'failed'
    codex_home = $CodexHome
    effective_default_cwd = $null
    hooks_dir = $null
    log_path = $null
    checks = @{}
    failed_checks = @('unexpected_error')
    locale_effective = $null
    dir_effective = $null
    legal_profile = $null
    compliance_summary = $null
    error = $_.Exception.Message
  } -ExitCode 1
}
