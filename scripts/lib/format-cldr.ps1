Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-I18nCulture {
  param([string]$Locale = 'en-US')

  try {
    return [System.Globalization.CultureInfo]::GetCultureInfo($Locale)
  } catch {
    return [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
  }
}

function Format-I18nTime {
  param(
    [datetimeoffset]$Value = ([datetimeoffset]::Now),
    [string]$Locale = 'en-US'
  )

  $culture = Get-I18nCulture -Locale $Locale
  return $Value.ToString('T', $culture)
}

function Format-I18nNumber {
  param(
    [double]$Value,
    [string]$Locale = 'en-US'
  )

  $culture = Get-I18nCulture -Locale $Locale
  return $Value.ToString('N', $culture)
}

function Format-I18nCurrency {
  param(
    [double]$Value,
    [string]$CurrencyCode = '',
    [string]$Locale = 'en-US'
  )

  $culture = Get-I18nCulture -Locale $Locale
  if ([string]::IsNullOrWhiteSpace($CurrencyCode)) {
    return $Value.ToString('C', $culture)
  }
  return ('{0} {1}' -f $Value.ToString('N2', $culture), $CurrencyCode.ToUpperInvariant())
}

function Get-I18nMaxTextElements {
  param(
    [string]$Locale = 'en-US',
    [int]$Default = 180
  )

  $base = $Locale.Split('-')[0].ToLowerInvariant()
  switch ($base) {
    'zh' { return 150 }
    'ar' { return 170 }
    default { return $Default }
  }
}

function Truncate-I18nText {
  param(
    [string]$Text,
    [int]$MaxTextElements = 180,
    [string]$Ellipsis = '...'
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $Text
  }

  $info = New-Object System.Globalization.StringInfo($Text)
  if ($info.LengthInTextElements -le $MaxTextElements) {
    return $Text
  }
  $sliceLen = [Math]::Max(0, $MaxTextElements - (New-Object System.Globalization.StringInfo($Ellipsis)).LengthInTextElements)
  $sliced = $info.SubstringByTextElements(0, $sliceLen)
  return $sliced + $Ellipsis
}
