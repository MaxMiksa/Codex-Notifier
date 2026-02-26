Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsRtlLocale {
  param([string]$Locale)

  if ([string]::IsNullOrWhiteSpace($Locale)) {
    return $false
  }
  $base = $Locale.Split('-')[0].ToLowerInvariant()
  return @('ar', 'he', 'fa', 'ur') -contains $base
}

function Get-DefaultDirectionForLocale {
  param([string]$Locale)

  if (Test-IsRtlLocale -Locale $Locale) {
    return 'rtl'
  }
  return 'ltr'
}

function Resolve-NotifierDirection {
  param(
    [string]$Dir = 'auto',
    [string]$Locale = 'en-US'
  )

  $requested = if ([string]::IsNullOrWhiteSpace($Dir)) { 'auto' } else { $Dir.Trim().ToLowerInvariant() }
  if (@('ltr', 'rtl') -contains $requested) {
    return [pscustomobject]@{
      dir_effective = $requested
      source = 'param'
      is_rtl = ($requested -eq 'rtl')
    }
  }

  $envDir = [Environment]::GetEnvironmentVariable('CODEX_NOTIFIER_DIR')
  if (-not [string]::IsNullOrWhiteSpace($envDir)) {
    $envNormalized = $envDir.Trim().ToLowerInvariant()
    if (@('ltr', 'rtl') -contains $envNormalized) {
      return [pscustomobject]@{
        dir_effective = $envNormalized
        source = 'env'
        is_rtl = ($envNormalized -eq 'rtl')
      }
    }
  }

  $auto = Get-DefaultDirectionForLocale -Locale $Locale
  return [pscustomobject]@{
    dir_effective = $auto
    source = 'auto'
    is_rtl = ($auto -eq 'rtl')
  }
}

function Get-LogicalDirectionMap {
  param([string]$Dir = 'ltr')

  if ($Dir -eq 'rtl') {
    return [ordered]@{
      inline_start = 'right'
      inline_end = 'left'
      text_align_start = 'right'
      text_align_end = 'left'
    }
  }

  return [ordered]@{
    inline_start = 'left'
    inline_end = 'right'
    text_align_start = 'left'
    text_align_end = 'right'
  }
}
