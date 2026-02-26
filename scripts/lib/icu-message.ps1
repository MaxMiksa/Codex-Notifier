Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-IcuArgsMap {
  param($ArgsObject)

  $result = @{}
  if ($null -eq $ArgsObject) {
    return $result
  }
  if ($ArgsObject -is [hashtable]) {
    foreach ($key in $ArgsObject.Keys) {
      $result[[string]$key] = $ArgsObject[$key]
    }
    return $result
  }
  foreach ($prop in $ArgsObject.PSObject.Properties) {
    $result[[string]$prop.Name] = $prop.Value
  }
  return $result
}

function Get-IcuNumericValue {
  param($Value, [double]$Default = 0)

  if ($null -eq $Value) {
    return $Default
  }
  $outNumber = 0.0
  if ([double]::TryParse(
      [string]$Value,
      [System.Globalization.NumberStyles]::Any,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$outNumber
    )) {
    return $outNumber
  }
  return $Default
}

function Get-IcuPluralCategory {
  param(
    [string]$Locale,
    [double]$Count
  )

  $localeName = if ([string]::IsNullOrWhiteSpace($Locale)) { 'en-US' } else { $Locale }
  $baseLocale = $localeName.Split('-')[0].ToLowerInvariant()
  $n = [math]::Abs([int][math]::Floor($Count))

  if ($baseLocale -eq 'zh') {
    return 'other'
  }

  if ($baseLocale -eq 'ar') {
    if ($n -eq 0) { return 'zero' }
    if ($n -eq 1) { return 'one' }
    if ($n -eq 2) { return 'two' }
    $mod100 = $n % 100
    if ($mod100 -ge 3 -and $mod100 -le 10) { return 'few' }
    if ($mod100 -ge 11 -and $mod100 -le 99) { return 'many' }
    return 'other'
  }

  if (($Count -eq 1) -or ($Count -eq -1)) {
    return 'one'
  }
  return 'other'
}

function Find-IcuMatchingBrace {
  param(
    [string]$Text,
    [int]$OpenIndex
  )

  $depth = 0
  for ($i = $OpenIndex; $i -lt $Text.Length; $i++) {
    $ch = $Text[$i]
    if ($ch -eq '{') {
      $depth++
      continue
    }
    if ($ch -eq '}') {
      $depth--
      if ($depth -eq 0) {
        return $i
      }
    }
  }
  return -1
}

function Parse-IcuPluralCases {
  param([string]$Body)

  $cases = @{}
  $i = 0
  while ($i -lt $Body.Length) {
    while ($i -lt $Body.Length -and [char]::IsWhiteSpace($Body[$i])) {
      $i++
    }
    if ($i -lt $Body.Length -and $Body[$i] -eq ',') {
      $i++
      continue
    }
    if ($i -ge $Body.Length) {
      break
    }

    $selectorStart = $i
    while ($i -lt $Body.Length -and -not [char]::IsWhiteSpace($Body[$i]) -and $Body[$i] -ne '{') {
      $i++
    }
    if ($selectorStart -eq $i) {
      break
    }
    $selector = $Body.Substring($selectorStart, $i - $selectorStart).Trim()

    while ($i -lt $Body.Length -and [char]::IsWhiteSpace($Body[$i])) {
      $i++
    }
    if ($i -ge $Body.Length -or $Body[$i] -ne '{') {
      break
    }

    $endBrace = Find-IcuMatchingBrace -Text $Body -OpenIndex $i
    if ($endBrace -lt 0) {
      break
    }
    $message = $Body.Substring($i + 1, $endBrace - $i - 1)
    $cases[$selector] = $message
    $i = $endBrace + 1
  }

  return $cases
}

function Resolve-IcuPluralMessage {
  param(
    [string]$Content,
    [string]$Locale,
    [hashtable]$ArgsMap
  )

  if ($Content -notmatch '^\s*([A-Za-z0-9_.-]+)\s*,\s*plural\s*,\s*(.+)$') {
    return $null
  }

  $countKey = $matches[1]
  $casesBody = $matches[2]
  $countValue = 0
  if ($ArgsMap.ContainsKey($countKey)) {
    $countValue = Get-IcuNumericValue -Value $ArgsMap[$countKey]
  }

  $cases = Parse-IcuPluralCases -Body $casesBody
  if (-not $cases.ContainsKey('other')) {
    throw "ICU plural template missing required 'other' case for key '$countKey'."
  }

  $exactKey = '=' + ([int][math]::Floor($countValue))
  $category = Get-IcuPluralCategory -Locale $Locale -Count $countValue
  $selected = $null
  if ($cases.ContainsKey($exactKey)) {
    $selected = [string]$cases[$exactKey]
  } elseif ($cases.ContainsKey($category)) {
    $selected = [string]$cases[$category]
  } else {
    $selected = [string]$cases['other']
  }

  $numberText = [string]$countValue
  $selected = $selected.Replace('#', $numberText)
  return Format-IcuMessage -Template $selected -Locale $Locale -ArgsMap $ArgsMap
}

function Expand-IcuPluralBlocks {
  param(
    [string]$Template,
    [string]$Locale,
    [hashtable]$ArgsMap
  )

  if ([string]::IsNullOrEmpty($Template)) {
    return $Template
  }

  $text = $Template
  $guard = 0
  while ($guard -lt 128) {
    $guard++
    $openIndex = $text.IndexOf('{')
    if ($openIndex -lt 0) {
      break
    }

    $replaced = $false
    $i = $openIndex
    while ($i -lt $text.Length) {
      if ($text[$i] -ne '{') {
        $i++
        continue
      }
      $endBrace = Find-IcuMatchingBrace -Text $text -OpenIndex $i
      if ($endBrace -lt 0) {
        break
      }
      $inner = $text.Substring($i + 1, $endBrace - $i - 1)
      $pluralResolved = Resolve-IcuPluralMessage -Content $inner -Locale $Locale -ArgsMap $ArgsMap
      if ($null -ne $pluralResolved) {
        $before = $text.Substring(0, $i)
        $after = $text.Substring($endBrace + 1)
        $text = $before + $pluralResolved + $after
        $replaced = $true
        break
      }
      $i = $endBrace + 1
    }

    if (-not $replaced) {
      break
    }
  }

  return $text
}

function Format-IcuMessage {
  param(
    [string]$Template,
    [string]$Locale = 'en-US',
    $ArgsObject = $null,
    [hashtable]$ArgsMap = $null
  )

  if ($null -eq $ArgsMap) {
    $ArgsMap = ConvertTo-IcuArgsMap -ArgsObject $ArgsObject
  }
  if ([string]::IsNullOrEmpty($Template)) {
    return $Template
  }

  $text = Expand-IcuPluralBlocks -Template $Template -Locale $Locale -ArgsMap $ArgsMap
  $result = [regex]::Replace(
    $text,
    '\{([A-Za-z0-9_.-]+)\}',
    {
      param($match)
      $name = [string]$match.Groups[1].Value
      if ($ArgsMap.ContainsKey($name) -and $null -ne $ArgsMap[$name]) {
        return [string]$ArgsMap[$name]
      }
      return $match.Value
    }
  )
  return $result
}
