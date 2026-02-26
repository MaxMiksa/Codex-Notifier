[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $HOME '.codex'),
  [string]$DefaultCwd = '',
  [string]$Locale = 'auto',
  [string]$LegalProfile = 'global-minimal',
  [switch]$Force,
  [switch]$NoSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\config-merge.ps1')
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

function Copy-FileIfNeeded {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [switch]$ForceCopy
  )

  $parent = Split-Path -Parent $TargetPath
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $same = Test-SameFileContent -SourcePath $SourcePath -TargetPath $TargetPath
  if (-not $same -or $ForceCopy.IsPresent) {
    Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    return $true
  }
  return $false
}

function Invoke-StopHookSmokeTest {
  param(
    [Parameter(Mandatory = $true)][string]$StopHookPath,
    [Parameter(Mandatory = $true)][string]$EffectiveDefaultCwd,
    [Parameter(Mandatory = $true)][string]$LocaleEffective,
    [Parameter(Mandatory = $true)][string]$DirEffective,
    [Parameter(Mandatory = $true)][string]$LegalProfileEffective
  )

  $payload = '{"type":"smoketest","event":"smoketest","thread-id":"install-smoketest","turn-id":"install-smoketest"}'
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

  $repoRoot = Split-Path -Path $PSScriptRoot -Parent
  $sourceStopHookPath = Join-Path $repoRoot 'hooks\notify-stop.ps1'
  $sourceClickHookPath = Join-Path $repoRoot 'hooks\notify-click-jump.ps1'
  $sourceLibDir = Join-Path $repoRoot 'scripts\lib'
  $sourceLocaleDir = Join-Path $repoRoot 'i18n\locales'
  $sourceSchemaDir = Join-Path $repoRoot 'i18n\schema'

  if (-not (Test-Path -LiteralPath $sourceStopHookPath) -or -not (Test-Path -LiteralPath $sourceClickHookPath)) {
    $missingHooksText = Get-I18nText -Key 'installer.error_missing_hooks' -Locale $effectiveLocale
    throw $missingHooksText
  }

  $hooksDir = Join-Path $CodexHome 'hooks'
  $hooksLibDir = Join-Path $hooksDir 'lib'
  $logsDir = Join-Path $hooksDir 'logs'
  $backupDir = Join-Path $CodexHome 'backup'
  $codexLocaleDir = Join-Path $CodexHome 'i18n\locales'
  $codexSchemaDir = Join-Path $CodexHome 'i18n\schema'
  foreach ($dir in @($CodexHome, $hooksDir, $hooksLibDir, $logsDir, $backupDir, $codexLocaleDir, $codexSchemaDir)) {
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
    if (Copy-FileIfNeeded -SourcePath $pair.source -TargetPath $pair.target -ForceCopy:$Force.IsPresent) {
      $filesChanged = $true
    }
  }

  $runtimeLibFiles = @(
    'i18n-core.ps1',
    'icu-message.ps1',
    'locale-resolver.ps1',
    'layout-direction.ps1',
    'format-cldr.ps1'
  )
  foreach ($libName in $runtimeLibFiles) {
    $sourceFile = Join-Path $sourceLibDir $libName
    $targetFile = Join-Path $hooksLibDir $libName
    if (Copy-FileIfNeeded -SourcePath $sourceFile -TargetPath $targetFile -ForceCopy:$Force.IsPresent) {
      $filesChanged = $true
    }
  }

  foreach ($localeFile in Get-ChildItem -LiteralPath $sourceLocaleDir -File -Filter '*.json') {
    $targetFile = Join-Path $codexLocaleDir $localeFile.Name
    if (Copy-FileIfNeeded -SourcePath $localeFile.FullName -TargetPath $targetFile -ForceCopy:$Force.IsPresent) {
      $filesChanged = $true
    }
  }
  foreach ($schemaFile in Get-ChildItem -LiteralPath $sourceSchemaDir -File -Filter '*.json') {
    $targetFile = Join-Path $codexSchemaDir $schemaFile.Name
    if (Copy-FileIfNeeded -SourcePath $schemaFile.FullName -TargetPath $targetFile -ForceCopy:$Force.IsPresent) {
      $filesChanged = $true
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
  $commandLocale = if ([string]::IsNullOrWhiteSpace($Locale)) { 'auto' } else { $Locale }
  $commandLegalProfile = if ([string]::IsNullOrWhiteSpace($LegalProfile)) { 'global-minimal' } else { $LegalProfile }

  $merge = Merge-CodexNotifierStopHook `
    -ConfigText $configText `
    -StopHookScriptPath $targetStopHookPath `
    -DefaultCwd $effectiveDefaultCwd `
    -TimeoutMs 4000 `
    -Locale $commandLocale `
    -LegalProfile $commandLegalProfile

  if ([bool]$merge.conflict) {
    Emit-ResultAndExit -Result @{
      status = 'conflict_manual_merge_required'
      config_backup_path = $backupPath
      installed_hook_paths = $installedHookPaths
      effective_default_cwd = $effectiveDefaultCwd
      locale_effective = $effectiveLocale
      dir_effective = $effectiveDir
      legal_profile = $effectiveLegalProfile
    } -ExitCode 20
  }

  $configChanged = [bool]$merge.changed
  if ($configChanged -or -not (Test-Path -LiteralPath $configPath)) {
    Write-Utf8NoBomFile -Path $configPath -Content ([string]$merge.new_text)
  }

  if (-not $NoSmokeTest.IsPresent) {
    $smokeExit = Invoke-StopHookSmokeTest `
      -StopHookPath $targetStopHookPath `
      -EffectiveDefaultCwd $effectiveDefaultCwd `
      -LocaleEffective $effectiveLocale `
      -DirEffective $effectiveDir `
      -LegalProfileEffective $effectiveLegalProfile
    if ($smokeExit -ne 0) {
      Emit-ResultAndExit -Result @{
        status = 'failed'
        config_backup_path = $backupPath
        installed_hook_paths = $installedHookPaths
        effective_default_cwd = $effectiveDefaultCwd
        locale_effective = $effectiveLocale
        dir_effective = $effectiveDir
        legal_profile = $effectiveLegalProfile
        error = (Get-I18nText -Key 'installer.error_smoke_failed' -Locale $effectiveLocale)
      } -ExitCode 1
    }
  }

  $status = if (-not $filesChanged -and -not $configChanged) { 'already_installed' } else { 'installed' }
  Emit-ResultAndExit -Result @{
    status = $status
    config_backup_path = $backupPath
    installed_hook_paths = $installedHookPaths
    effective_default_cwd = $effectiveDefaultCwd
    locale_effective = $effectiveLocale
    dir_effective = $effectiveDir
    legal_profile = $effectiveLegalProfile
  } -ExitCode 0
} catch {
  Emit-ResultAndExit -Result @{
    status = 'failed'
    config_backup_path = $null
    installed_hook_paths = @()
    effective_default_cwd = $null
    locale_effective = $null
    dir_effective = $null
    legal_profile = $null
    error = $_.Exception.Message
  } -ExitCode 1
}
