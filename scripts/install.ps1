[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $HOME '.codex'),
  [string]$DefaultCwd = '',
  [switch]$Force,
  [switch]$NoSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\config-merge.ps1')

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

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Test-SameFileContent {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TargetPath
  )

  if (-not (Test-Path -LiteralPath $SourcePath) -or -not (Test-Path -LiteralPath $TargetPath)) {
    return $false
  }
  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash
  $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetPath).Hash
  return $sourceHash -eq $targetHash
}

function Invoke-StopHookSmokeTest {
  param(
    [Parameter(Mandatory = $true)][string]$StopHookPath,
    [Parameter(Mandatory = $true)][string]$EffectiveDefaultCwd
  )

  $payload = '{"type":"smoketest","event":"smoketest","thread-id":"install-smoketest","turn-id":"install-smoketest"}'
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
  $repoRoot = Split-Path -Path $PSScriptRoot -Parent
  $sourceStopHookPath = Join-Path $repoRoot 'hooks\notify-stop.ps1'
  $sourceClickHookPath = Join-Path $repoRoot 'hooks\notify-click-jump.ps1'
  if (-not (Test-Path -LiteralPath $sourceStopHookPath) -or -not (Test-Path -LiteralPath $sourceClickHookPath)) {
    throw 'Missing hook scripts in repository. Expected hooks/notify-stop.ps1 and hooks/notify-click-jump.ps1.'
  }

  $hooksDir = Join-Path $CodexHome 'hooks'
  $logsDir = Join-Path $hooksDir 'logs'
  $backupDir = Join-Path $CodexHome 'backup'
  foreach ($dir in @($CodexHome, $hooksDir, $logsDir, $backupDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
  }

  $targetStopHookPath = Join-Path $hooksDir 'notify-stop.ps1'
  $targetClickHookPath = Join-Path $hooksDir 'notify-click-jump.ps1'
  $installedHookPaths = @($targetStopHookPath, $targetClickHookPath)
  $filesChanged = $false

  foreach ($pair in @(
      @{ source = $sourceStopHookPath; target = $targetStopHookPath },
      @{ source = $sourceClickHookPath; target = $targetClickHookPath }
    )) {
    $same = Test-SameFileContent -SourcePath $pair.source -TargetPath $pair.target
    if (-not $same -or $Force.IsPresent) {
      Copy-Item -LiteralPath $pair.source -Destination $pair.target -Force
      if (-not $same) {
        $filesChanged = $true
      }
    }
  }

  $configPath = Join-Path $CodexHome 'config.toml'
  $backupPath = $null
  $configText = ''
  if (Test-Path -LiteralPath $configPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir ("config-{0}.toml" -f $timestamp)
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    $configText = Get-Content -LiteralPath $configPath -Raw
  }

  $effectiveDefaultCwd = Resolve-EffectiveDefaultCwd -Configured $DefaultCwd
  $merge = Merge-CodexNotifierStopHook `
    -ConfigText $configText `
    -StopHookScriptPath $targetStopHookPath `
    -DefaultCwd $effectiveDefaultCwd `
    -TimeoutMs 4000

  if ([bool]$merge.conflict) {
    Emit-ResultAndExit -Result @{
      status = 'conflict_manual_merge_required'
      config_backup_path = $backupPath
      installed_hook_paths = $installedHookPaths
      effective_default_cwd = $effectiveDefaultCwd
    } -ExitCode 20
  }

  $configChanged = [bool]$merge.changed
  if ($configChanged -or -not (Test-Path -LiteralPath $configPath)) {
    Write-Utf8NoBomFile -Path $configPath -Content ([string]$merge.new_text)
  }

  if (-not $NoSmokeTest.IsPresent) {
    $smokeExit = Invoke-StopHookSmokeTest -StopHookPath $targetStopHookPath -EffectiveDefaultCwd $effectiveDefaultCwd
    if ($smokeExit -ne 0) {
      Emit-ResultAndExit -Result @{
        status = 'failed'
        config_backup_path = $backupPath
        installed_hook_paths = $installedHookPaths
        effective_default_cwd = $effectiveDefaultCwd
        error = 'smoke_test_failed'
      } -ExitCode 1
    }
  }

  $status = if (-not $filesChanged -and -not $configChanged) { 'already_installed' } else { 'installed' }
  Emit-ResultAndExit -Result @{
    status = $status
    config_backup_path = $backupPath
    installed_hook_paths = $installedHookPaths
    effective_default_cwd = $effectiveDefaultCwd
  } -ExitCode 0
} catch {
  Emit-ResultAndExit -Result @{
    status = 'failed'
    config_backup_path = $null
    installed_hook_paths = @()
    effective_default_cwd = $null
    error = $_.Exception.Message
  } -ExitCode 1
}
