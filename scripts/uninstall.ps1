[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $HOME '.codex'),
  [switch]$KeepLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
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
  $hooksDir = Join-Path $CodexHome 'hooks'
  $backupDir = Join-Path $CodexHome 'backup'
  if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  }

  $configPath = Join-Path $CodexHome 'config.toml'
  $backupPath = $null
  $configChanged = $false

  if (Test-Path -LiteralPath $configPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir ("config-uninstall-{0}.toml" -f $timestamp)
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force

    $configText = Get-Content -LiteralPath $configPath -Raw
    $pattern = '(?ms)^\s*# codex-notifier managed block start\s*\r?\n.*?^\s*# codex-notifier managed block end\s*\r?\n?'
    $newText = [regex]::Replace($configText, $pattern, '')
    if ($newText -ne $configText) {
      Write-Utf8NoBomFile -Path $configPath -Content $newText
      $configChanged = $true
    }
  }

  $removedFiles = @()
  $targetFiles = @(
    (Join-Path $hooksDir 'notify-stop.ps1'),
    (Join-Path $hooksDir 'notify-click-jump.ps1')
  )
  foreach ($file in $targetFiles) {
    if (Test-Path -LiteralPath $file) {
      Remove-Item -LiteralPath $file -Force
      $removedFiles += $file
    }
  }

  if (-not $KeepLogs.IsPresent) {
    $contextFiles = Join-Path $hooksDir 'logs\notify-click-context-*.json'
    Get-ChildItem -LiteralPath (Split-Path $contextFiles -Parent) -Filter (Split-Path $contextFiles -Leaf) -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }

  $status = if ($configChanged -or $removedFiles.Count -gt 0) { 'uninstalled' } else { 'not_installed' }
  Emit-ResultAndExit -Result @{
    status = $status
    codex_home = $CodexHome
    config_backup_path = $backupPath
    removed_files = $removedFiles
    managed_block_removed = $configChanged
  } -ExitCode 0
} catch {
  Emit-ResultAndExit -Result @{
    status = 'failed'
    codex_home = $CodexHome
    config_backup_path = $null
    removed_files = @()
    managed_block_removed = $false
    error = $_.Exception.Message
  } -ExitCode 1
}
