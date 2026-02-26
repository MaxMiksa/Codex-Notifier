Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:I18nCoreLibRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Command -Name Format-IcuMessage -ErrorAction SilentlyContinue)) {
  . (Join-Path $script:I18nCoreLibRoot 'icu-message.ps1')
}

$script:I18nLocaleCache = @{}

function Get-NotifierBaseDir {
  $overrideBase = [Environment]::GetEnvironmentVariable('CODEX_NOTIFIER_BASE')
  if (-not [string]::IsNullOrWhiteSpace($overrideBase) -and (Test-Path -LiteralPath $overrideBase)) {
    return $overrideBase
  }

  $baseRoot = if (-not [string]::IsNullOrWhiteSpace($script:I18nCoreLibRoot)) { $script:I18nCoreLibRoot } else { $PSScriptRoot }
  $twoUp = Split-Path -Parent (Split-Path -Parent $baseRoot)
  if (Test-Path -LiteralPath (Join-Path $twoUp 'i18n\locales')) {
    return $twoUp
  }

  $oneUp = Split-Path -Parent $baseRoot
  if (Test-Path -LiteralPath (Join-Path $oneUp 'i18n\locales')) {
    return $oneUp
  }

  return $twoUp
}

function Get-I18nLocalesRoot {
  return (Join-Path (Get-NotifierBaseDir) 'i18n\locales')
}

function Get-I18nLocaleObject {
  param(
    [Parameter(Mandatory = $true)][string]$Locale,
    [string]$LocalesRoot = (Get-I18nLocalesRoot)
  )

  $cacheKey = "$LocalesRoot|$Locale"
  if ($script:I18nLocaleCache.ContainsKey($cacheKey)) {
    return $script:I18nLocaleCache[$cacheKey]
  }

  $path = Join-Path $LocalesRoot ("{0}.json" -f $Locale)
  if (-not (Test-Path -LiteralPath $path)) {
    return $null
  }
  $raw = Get-Content -LiteralPath $path -Raw
  $obj = $raw | ConvertFrom-Json
  $script:I18nLocaleCache[$cacheKey] = $obj
  return $obj
}

function Get-NestedI18nValue {
  param(
    [object]$Object,
    [string]$KeyPath
  )

  if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($KeyPath)) {
    return $null
  }
  $current = $Object
  foreach ($part in $KeyPath.Split('.')) {
    if ($null -eq $current) {
      return $null
    }
    $prop = $current.PSObject.Properties[$part]
    if ($null -eq $prop) {
      return $null
    }
    $current = $prop.Value
  }
  return $current
}

function Resolve-I18nValue {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Locale = 'en-US',
    [string]$FallbackLocale = 'en-US',
    [string]$LocalesRoot = (Get-I18nLocalesRoot)
  )

  $requested = if ([string]::IsNullOrWhiteSpace($Locale)) { $FallbackLocale } else { $Locale }
  $primaryObj = Get-I18nLocaleObject -Locale $requested -LocalesRoot $LocalesRoot
  $value = Get-NestedI18nValue -Object $primaryObj -KeyPath $Key
  if ($null -ne $value) {
    return [pscustomobject]@{
      value = $value
      key = $Key
      locale_used = $requested
      fallback_used = $false
      key_found = $true
    }
  }

  $fallbackObj = Get-I18nLocaleObject -Locale $FallbackLocale -LocalesRoot $LocalesRoot
  $fallbackValue = Get-NestedI18nValue -Object $fallbackObj -KeyPath $Key
  if ($null -ne $fallbackValue) {
    return [pscustomobject]@{
      value = $fallbackValue
      key = $Key
      locale_used = $FallbackLocale
      fallback_used = $true
      key_found = $true
    }
  }

  return [pscustomobject]@{
    value = $null
    key = $Key
    locale_used = $FallbackLocale
    fallback_used = $true
    key_found = $false
  }
}

function Resolve-I18nText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Locale = 'en-US',
    [string]$FallbackLocale = 'en-US',
    $ArgsObject = $null,
    [string]$DefaultText = ''
  )

  $valueResult = Resolve-I18nValue -Key $Key -Locale $Locale -FallbackLocale $FallbackLocale
  $text = $null
  if ($valueResult.key_found) {
    if ($valueResult.value -is [string]) {
      $text = Format-IcuMessage -Template ([string]$valueResult.value) -Locale $valueResult.locale_used -ArgsObject $ArgsObject
    } else {
      $text = [string]$valueResult.value
    }
  } else {
    $text = if ([string]::IsNullOrWhiteSpace($DefaultText)) { $Key } else { $DefaultText }
  }

  return [pscustomobject]@{
    text = $text
    key = $Key
    locale_used = $valueResult.locale_used
    fallback_used = [bool]$valueResult.fallback_used
    key_found = [bool]$valueResult.key_found
  }
}

function Get-I18nText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Locale = 'en-US',
    [string]$FallbackLocale = 'en-US',
    $ArgsObject = $null,
    [string]$DefaultText = ''
  )

  $resolved = Resolve-I18nText -Key $Key -Locale $Locale -FallbackLocale $FallbackLocale -ArgsObject $ArgsObject -DefaultText $DefaultText
  return [string]$resolved.text
}

function Get-I18nList {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Locale = 'en-US',
    [string]$FallbackLocale = 'en-US'
  )

  $resolved = Resolve-I18nValue -Key $Key -Locale $Locale -FallbackLocale $FallbackLocale
  if ($resolved.value -is [System.Collections.IEnumerable] -and -not ($resolved.value -is [string])) {
    $items = @()
    foreach ($item in $resolved.value) {
      $items += [string]$item
    }
    return [pscustomobject]@{
      items = $items
      key = $Key
      locale_used = $resolved.locale_used
      fallback_used = [bool]$resolved.fallback_used
      key_found = [bool]$resolved.key_found
    }
  }
  return [pscustomobject]@{
    items = @()
    key = $Key
    locale_used = $resolved.locale_used
    fallback_used = [bool]$resolved.fallback_used
    key_found = $false
  }
}

function Get-I18nLegalNotices {
  param(
    [string]$Locale = 'en-US',
    [string]$FallbackLocale = 'en-US'
  )

  return [ordered]@{
    privacy = Get-I18nText -Key 'legal.privacy_notice' -Locale $Locale -FallbackLocale $FallbackLocale
    localProcessing = Get-I18nText -Key 'legal.local_processing_notice' -Locale $Locale -FallbackLocale $FallbackLocale
    noUpload = Get-I18nText -Key 'legal.no_upload_notice' -Locale $Locale -FallbackLocale $FallbackLocale
    audit = Get-I18nText -Key 'legal.audit_log_notice' -Locale $Locale -FallbackLocale $FallbackLocale
  }
}
