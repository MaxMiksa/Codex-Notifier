[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $HOME '.codex'),
  [string]$DefaultCwd = '',
  [switch]$RunSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    [Parameter(Mandatory = $true)][string]$EffectiveDefaultCwd
  )

  $payload = '{"type":"smoketest","event":"smoketest","thread-id":"doctor-smoketest","turn-id":"doctor-smoketest"}'
  $payload | & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $StopHookPath -DefaultCwd $EffectiveDefaultCwd
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
  $effectiveDefaultCwd = Resolve-EffectiveDefaultCwd -Configured $DefaultCwd
  $hooksDir = Join-Path $CodexHome 'hooks'
  $logsPath = Join-Path $hooksDir 'logs\notify-stop-events.jsonl'
  $stopHookPath = Join-Path $hooksDir 'notify-stop.ps1'
  $clickHookPath = Join-Path $hooksDir 'notify-click-jump.ps1'
  $configPath = Join-Path $CodexHome 'config.toml'

  $checks = [ordered]@{
    stop_hook_exists = (Test-Path -LiteralPath $stopHookPath)
    click_hook_exists = (Test-Path -LiteralPath $clickHookPath)
    config_exists = (Test-Path -LiteralPath $configPath)
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
    $checks.smoke_test_ok = ((Invoke-StopHookSmokeTest -StopHookPath $stopHookPath -EffectiveDefaultCwd $effectiveDefaultCwd) -eq 0)
  }

  $failed = @()
  foreach ($item in @('stop_hook_exists', 'click_hook_exists', 'config_exists', 'managed_block_present', 'stop_entry_present')) {
    if (-not [bool]$checks[$item]) {
      $failed += $item
    }
  }
  if ($RunSmokeTest.IsPresent -and -not [bool]$checks.smoke_test_ok) {
    $failed += 'smoke_test_ok'
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
    error = $_.Exception.Message
  } -ExitCode 1
}
