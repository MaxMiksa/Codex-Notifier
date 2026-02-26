Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SupportedNotifierLocales {
  return @('en-US', 'zh-CN', 'ar-XB')
}

function Normalize-NotifierLocale {
  param(
    [string]$Locale,
    [string[]]$SupportedLocales = (Get-SupportedNotifierLocales)
  )

  if ([string]::IsNullOrWhiteSpace($Locale)) {
    return $null
  }

  foreach ($candidate in $SupportedLocales) {
    if ($candidate.Equals($Locale, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $candidate
    }
  }

  $base = $Locale.Split('-')[0].ToLowerInvariant()
  if ($base -eq 'en' -and $SupportedLocales -contains 'en-US') { return 'en-US' }
  if ($base -eq 'zh' -and $SupportedLocales -contains 'zh-CN') { return 'zh-CN' }
  if ($base -eq 'ar' -and $SupportedLocales -contains 'ar-XB') { return 'ar-XB' }
  return $null
}

function Resolve-NotifierLocale {
  param(
    [string]$Locale = '',
    [string[]]$SupportedLocales = (Get-SupportedNotifierLocales),
    [string]$FallbackLocale = 'en-US'
  )

  $requested = if ([string]::IsNullOrWhiteSpace($Locale)) { 'auto' } else { $Locale.Trim() }
  if ($requested -ne 'auto') {
    $normalized = Normalize-NotifierLocale -Locale $requested -SupportedLocales $SupportedLocales
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
      return [pscustomobject]@{
        locale = $normalized
        source = 'param'
        fallback_used = $false
      }
    }
  }

  $envLocale = [Environment]::GetEnvironmentVariable('CODEX_NOTIFIER_LOCALE')
  if (-not [string]::IsNullOrWhiteSpace($envLocale) -and $envLocale.Trim() -ne 'auto') {
    $normalizedEnv = Normalize-NotifierLocale -Locale $envLocale.Trim() -SupportedLocales $SupportedLocales
    if (-not [string]::IsNullOrWhiteSpace($normalizedEnv)) {
      return [pscustomobject]@{
        locale = $normalizedEnv
        source = 'env'
        fallback_used = $false
      }
    }
  }

  $systemLocale = [System.Globalization.CultureInfo]::CurrentUICulture.Name
  $normalizedSystem = Normalize-NotifierLocale -Locale $systemLocale -SupportedLocales $SupportedLocales
  if (-not [string]::IsNullOrWhiteSpace($normalizedSystem)) {
    return [pscustomobject]@{
      locale = $normalizedSystem
      source = 'system'
      fallback_used = $false
    }
  }

  return [pscustomobject]@{
    locale = $FallbackLocale
    source = 'fallback'
    fallback_used = $true
  }
}

function Resolve-NotifierLegalProfile {
  param(
    [string]$LegalProfile = '',
    [string]$Default = 'global-minimal'
  )

  $allowed = @('global-minimal')
  if (-not [string]::IsNullOrWhiteSpace($LegalProfile)) {
    $candidate = $LegalProfile.Trim().ToLowerInvariant()
    if ($allowed -contains $candidate) {
      return [pscustomobject]@{
        legal_profile = $candidate
        source = 'param'
      }
    }
  }

  $envProfile = [Environment]::GetEnvironmentVariable('CODEX_NOTIFIER_LEGAL_PROFILE')
  if (-not [string]::IsNullOrWhiteSpace($envProfile)) {
    $candidate = $envProfile.Trim().ToLowerInvariant()
    if ($allowed -contains $candidate) {
      return [pscustomobject]@{
        legal_profile = $candidate
        source = 'env'
      }
    }
  }

  return [pscustomobject]@{
    legal_profile = $Default
    source = 'default'
  }
}
