param(
  [string]$DefaultCwd = '',
  [string]$Locale = 'auto',
  [string]$Dir = 'auto',
  [string]$LegalProfile = 'global-minimal'
)

$ErrorActionPreference = 'Stop'

function Resolve-NotifierLibPath {
  param([Parameter(Mandatory = $true)][string]$FileName)

  $candidates = @(
    (Join-Path $PSScriptRoot ("lib\{0}" -f $FileName)),
    (Join-Path (Split-Path -Parent $PSScriptRoot) ("scripts\lib\{0}" -f $FileName))
  )
  foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
      return $path
    }
  }
  return $null
}

foreach ($libName in @('icu-message.ps1', 'i18n-core.ps1', 'locale-resolver.ps1', 'layout-direction.ps1', 'format-cldr.ps1')) {
  $libPath = Resolve-NotifierLibPath -FileName $libName
  if (-not [string]::IsNullOrWhiteSpace($libPath)) {
    . $libPath
  }
}

if (-not (Get-Command -Name Resolve-NotifierLocale -ErrorAction SilentlyContinue)) {
  function Resolve-NotifierLocale {
    param([string]$Locale = '', [string]$FallbackLocale = 'en-US')
    $effective = if ([string]::IsNullOrWhiteSpace($Locale) -or $Locale -eq 'auto') { $FallbackLocale } else { $Locale }
    return [pscustomobject]@{ locale = $effective; source = 'fallback'; fallback_used = $true }
  }
}
if (-not (Get-Command -Name Resolve-NotifierDirection -ErrorAction SilentlyContinue)) {
  function Resolve-NotifierDirection {
    param([string]$Dir = 'auto', [string]$Locale = 'en-US')
    $effective = if ($Dir -eq 'ltr' -or $Dir -eq 'rtl') { $Dir } elseif ($Locale -like 'ar*') { 'rtl' } else { 'ltr' }
    return [pscustomobject]@{ dir_effective = $effective; source = 'fallback'; is_rtl = ($effective -eq 'rtl') }
  }
}
if (-not (Get-Command -Name Resolve-NotifierLegalProfile -ErrorAction SilentlyContinue)) {
  function Resolve-NotifierLegalProfile {
    param([string]$LegalProfile = '')
    $effective = if ([string]::IsNullOrWhiteSpace($LegalProfile)) { 'global-minimal' } else { $LegalProfile }
    return [pscustomobject]@{ legal_profile = $effective; source = 'fallback' }
  }
}
if (-not (Get-Command -Name Format-I18nTime -ErrorAction SilentlyContinue)) {
  function Format-I18nTime {
    param([datetimeoffset]$Value = ([datetimeoffset]::Now), [string]$Locale = 'en-US')
    return $Value.ToString('T', [System.Globalization.CultureInfo]::InvariantCulture)
  }
}
if (-not (Get-Command -Name Get-I18nMaxTextElements -ErrorAction SilentlyContinue)) {
  function Get-I18nMaxTextElements {
    param([string]$Locale = 'en-US', [int]$Default = 180)
    return $Default
  }
}
if (-not (Get-Command -Name Truncate-I18nText -ErrorAction SilentlyContinue)) {
  function Truncate-I18nText {
    param([string]$Text, [int]$MaxTextElements = 180, [string]$Ellipsis = '...')
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    if ($Text.Length -le $MaxTextElements) { return $Text }
    return $Text.Substring(0, [Math]::Max(0, $MaxTextElements - $Ellipsis.Length)) + $Ellipsis
  }
}

function Resolve-NotifierDefaultCwd {
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

function Resolve-I18nTextSafe {
  param(
    [string]$Key,
    [string]$LocaleValue,
    $ArgsObject = $null,
    [string]$DefaultText = ''
  )

  if (Get-Command -Name Resolve-I18nText -ErrorAction SilentlyContinue) {
    return Resolve-I18nText -Key $Key -Locale $LocaleValue -ArgsObject $ArgsObject -DefaultText $DefaultText
  }
  return [pscustomobject]@{
    text = if ([string]::IsNullOrWhiteSpace($DefaultText)) { $Key } else { $DefaultText }
    key = $Key
    locale_used = $LocaleValue
    fallback_used = $true
    key_found = $false
  }
}

function Get-I18nListSafe {
  param(
    [string]$Key,
    [string]$LocaleValue
  )

  if (Get-Command -Name Get-I18nList -ErrorAction SilentlyContinue) {
    return Get-I18nList -Key $Key -Locale $LocaleValue
  }
  return [pscustomobject]@{
    items = @('summary:', 'Summary:')
    key = $Key
    locale_used = $LocaleValue
    fallback_used = $true
    key_found = $false
  }
}

function Normalize-OneLine {
  param(
    [string]$Text,
    [string[]]$TrimPrefixes,
    [int]$MaxElements = 72
  )

  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $oneLine = $Text -replace '[\r\n\t]+', ' '
  $oneLine = $oneLine -replace '\s{2,}', ' '
  $oneLine = $oneLine.Trim()
  $oneLine = $oneLine.TrimStart('#', '-', '*', '`', '>', ' ')

  $removed = $true
  while ($removed -and -not [string]::IsNullOrWhiteSpace($oneLine)) {
    $removed = $false
    foreach ($prefix in $TrimPrefixes) {
      if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
      if ($oneLine.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $oneLine = $oneLine.Substring($prefix.Length).Trim()
        $removed = $true
      }
    }
  }

  if (Get-Command -Name Truncate-I18nText -ErrorAction SilentlyContinue) {
    return Truncate-I18nText -Text $oneLine -MaxTextElements $MaxElements
  }
  if ($oneLine.Length -gt $MaxElements) {
    return $oneLine.Substring(0, $MaxElements) + '...'
  }
  return $oneLine
}

function Get-FirstContentLine {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  foreach ($line in ($Text -split "\r?\n")) {
    $trimmed = $line.Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
      return $trimmed
    }
  }
  return $null
}

function Get-MessageLikeText {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $last = $null
    foreach ($item in $Value) {
      if ($null -ne $item) { $last = $item }
    }
    if ($null -eq $last) { return $null }
    if ($last -is [string]) { return $last }
    $lastText = $last.PSObject.Properties['text']
    if ($null -ne $lastText -and -not [string]::IsNullOrWhiteSpace([string]$lastText.Value)) {
      return [string]$lastText.Value
    }
    return [string]$last
  }
  $textProp = $Value.PSObject.Properties['text']
  if ($null -ne $textProp -and -not [string]::IsNullOrWhiteSpace([string]$textProp.Value)) {
    return [string]$textProp.Value
  }
  return [string]$Value
}

function New-RuleSummary {
  param(
    [object]$Payload,
    [bool]$IsSuccess,
    [string]$EventType,
    [string]$EventName,
    [string]$LocaleValue,
    [string[]]$TrimPrefixes
  )

  $assistantLine = $null
  $inputLine = $null

  if ($null -ne $Payload) {
    $assistantProp = $Payload.PSObject.Properties['last-assistant-message']
    if ($null -ne $assistantProp) {
      $assistantRaw = Get-MessageLikeText $assistantProp.Value
      $assistantLine = Normalize-OneLine -Text (Get-FirstContentLine $assistantRaw) -TrimPrefixes $TrimPrefixes -MaxElements 72
    }

    $inputProp = $Payload.PSObject.Properties['input-messages']
    if ($null -ne $inputProp) {
      $inputRaw = Get-MessageLikeText $inputProp.Value
      $inputLine = Normalize-OneLine -Text (Get-FirstContentLine $inputRaw) -TrimPrefixes $TrimPrefixes -MaxElements 72
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($assistantLine)) {
    return [pscustomobject]@{ Text = $assistantLine; Mode = 'assistant'; MessageKey = 'summary.assistant'; FallbackUsed = $false }
  }
  if (-not [string]::IsNullOrWhiteSpace($inputLine)) {
    return [pscustomobject]@{ Text = $inputLine; Mode = 'input'; MessageKey = 'summary.input'; FallbackUsed = $false }
  }

  if ($EventType -eq 'agent-turn-complete' -or $IsSuccess) {
    $resolved = Resolve-I18nTextSafe -Key 'notifications.fallback_success' -LocaleValue $LocaleValue
    return [pscustomobject]@{
      Text = [string]$resolved.text
      Mode = 'fallback_success'
      MessageKey = 'notifications.fallback_success'
      FallbackUsed = [bool]$resolved.fallback_used
    }
  }
  if ($EventName -eq 'Stop') {
    $resolved = Resolve-I18nTextSafe -Key 'notifications.fallback_stop' -LocaleValue $LocaleValue
    return [pscustomobject]@{
      Text = [string]$resolved.text
      Mode = 'fallback_stop'
      MessageKey = 'notifications.fallback_stop'
      FallbackUsed = [bool]$resolved.fallback_used
    }
  }

  $resolvedUnknown = Resolve-I18nTextSafe -Key 'notifications.fallback_unknown' -LocaleValue $LocaleValue
  return [pscustomobject]@{
    Text = [string]$resolvedUnknown.text
    Mode = 'fallback_unknown'
    MessageKey = 'notifications.fallback_unknown'
    FallbackUsed = [bool]$resolvedUnknown.fallback_used
  }
}

function Get-HardFinalMarker {
  param([object]$Payload)
  if ($null -eq $Payload) {
    return [pscustomobject]@{ Found = $false; Key = $null; Value = $null }
  }

  $candidates = @(
    'is-final', 'is_final', 'is-final-turn', 'is_final_turn',
    'final', 'final-turn', 'final_response', 'is-user-visible', 'is_user_visible'
  )
  foreach ($key in $candidates) {
    $prop = $Payload.PSObject.Properties[$key]
    if ($null -ne $prop) {
      return [pscustomobject]@{ Found = $true; Key = $key; Value = $prop.Value }
    }
  }
  return [pscustomobject]@{ Found = $false; Key = $null; Value = $null }
}

function Test-Truthy {
  param($Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return [bool]$Value }
  $s = ([string]$Value).Trim().ToLowerInvariant()
  return @('1', 'true', 'yes', 'y', 'done', 'final') -contains $s
}

function Test-ShouldNotifyWithFallback {
  param(
    [bool]$ParseOk,
    [string]$EventType,
    [string]$SummaryMode,
    [string]$ThreadId,
    [string]$SummaryText
  )

  if (-not $ParseOk) { return [pscustomobject]@{ Notify = $false; Reason = 'skip_parse_failed' } }
  if ($EventType -ne 'agent-turn-complete') { return [pscustomobject]@{ Notify = $false; Reason = 'skip_not_turn_complete' } }
  if ($SummaryMode -ne 'assistant') { return [pscustomobject]@{ Notify = $false; Reason = 'skip_no_assistant_summary' } }
  if ([string]::IsNullOrWhiteSpace($ThreadId)) { return [pscustomobject]@{ Notify = $false; Reason = 'skip_missing_thread_id' } }
  if ([string]::IsNullOrWhiteSpace($SummaryText)) { return [pscustomobject]@{ Notify = $false; Reason = 'skip_empty_summary' } }

  $summary = $SummaryText.Trim()
  if ($summary -match '^[\{\[]') { return [pscustomobject]@{ Notify = $false; Reason = 'skip_summary_json_like' } }
  if ($summary -match '^\d+[\.\)]\s+') { return [pscustomobject]@{ Notify = $false; Reason = 'skip_summary_list_item' } }
  if ($summary -match '\*\*$' -and $summary -notmatch '[。.!?！？]$') { return [pscustomobject]@{ Notify = $false; Reason = 'skip_summary_heading_like' } }

  $statePath = Join-Path $HOME '.codex\hooks\logs\notify-stop-state.json'
  $now = [DateTimeOffset]::Now
  $threadCooldownSec = 8
  try {
    if (Test-Path -LiteralPath $statePath) {
      $stateRaw = Get-Content -Raw -LiteralPath $statePath
      if (-not [string]::IsNullOrWhiteSpace($stateRaw)) {
        $state = $stateRaw | ConvertFrom-Json
        $prevThread = [string]$state.thread_id
        $prevTsRaw = [string]$state.ts_iso
        if (-not [string]::IsNullOrWhiteSpace($prevTsRaw)) {
          $prevTs = [DateTimeOffset]::Parse($prevTsRaw)
          $delta = ($now - $prevTs).TotalSeconds
          if (($ThreadId -eq $prevThread) -and ($delta -lt $threadCooldownSec)) {
            return [pscustomobject]@{ Notify = $false; Reason = 'skip_dedup_thread_cooldown' }
          }
        }
      }
    }
  } catch {}

  try {
    $stateObj = [ordered]@{
      thread_id = $ThreadId
      ts_iso = $now.ToString('o')
    }
    $stateJson = $stateObj | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($statePath, $stateJson, [System.Text.UTF8Encoding]::new($false))
  } catch {}

  return [pscustomobject]@{ Notify = $true; Reason = 'notify_fallback_rules_passed' }
}

function Resolve-TargetCwd {
  param(
    [object]$Payload,
    [string]$FallbackCwd
  )

  $candidate = $null
  if ($null -ne $Payload) {
    $cwdProp = $Payload.PSObject.Properties['cwd']
    if ($null -ne $cwdProp -and -not [string]::IsNullOrWhiteSpace([string]$cwdProp.Value)) {
      $candidate = [string]$cwdProp.Value
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
    return $candidate
  }
  return $FallbackCwd
}

function Truncate-ErrorMessage {
  param([string]$Message, [int]$MaxLen = 240)
  if ([string]::IsNullOrWhiteSpace($Message)) { return $null }
  $oneLine = ($Message -replace '[\r\n\t]+', ' ').Trim()
  if ($oneLine.Length -gt $MaxLen) {
    return $oneLine.Substring(0, $MaxLen) + '...'
  }
  return $oneLine
}

function Show-DirectBalloon {
  param(
    [string]$Title,
    [string]$Body,
    [bool]$IsSuccess
  )

  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    if ($IsSuccess) {
      $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
      $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    } else {
      $notifyIcon.Icon = [System.Drawing.SystemIcons]::Error
      $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
    }
    $notifyIcon.Visible = $true
    $notifyIcon.BalloonTipTitle = $Title
    $notifyIcon.BalloonTipText = $Body
    $notifyIcon.ShowBalloonTip(2500)
    Start-Sleep -Milliseconds 1800
    $notifyIcon.Dispose()
    return $true
  } catch {
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    Write-Host "$Title - $Body"
    return $false
  }
}

function Start-ClickNotifyWorker {
  param(
    [string]$Title,
    [string]$Body,
    [string]$Cwd,
    [string]$DefaultCwdValue,
    [string]$ThreadId,
    [string]$TurnId,
    [string]$EventType,
    [string]$EventName,
    [string]$InputSource,
    [bool]$ParseOk,
    [int]$PayloadLen,
    [string]$RawPreview,
    [string]$PayloadKeys,
    [string]$SummaryMode,
    [string]$SummaryText,
    [string]$DecisionMode,
    [bool]$HardMarkerFound,
    [string]$HardMarkerKey,
    [string]$HardMarkerValue,
    [bool]$NotifySent,
    [string]$NotifyReason,
    [bool]$IsSuccess,
    [string]$LocaleValue,
    [string]$DirValue,
    [string]$LegalProfileValue,
    [bool]$I18nFallbackUsed,
    [string]$MessageKey
  )

  $clickScriptCandidates = @(
    (Join-Path $PSScriptRoot 'notify-click-jump.ps1'),
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'hooks\notify-click-jump.ps1')
  )
  $clickScriptPath = $null
  foreach ($candidate in $clickScriptCandidates) {
    if (Test-Path -LiteralPath $candidate) {
      $clickScriptPath = $candidate
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($clickScriptPath)) {
    return [pscustomobject]@{
      Started = $false
      Error = 'click script missing'
    }
  }

  try {
    $context = [ordered]@{
      title = $Title
      body = $Body
      cwd = $Cwd
      default_cwd = $DefaultCwdValue
      thread_id = $ThreadId
      turn_id = $TurnId
      event_type = $EventType
      event_name = $EventName
      input_source = $InputSource
      parse_ok = [bool]$ParseOk
      payload_len = [int]$PayloadLen
      raw_preview = $RawPreview
      payload_keys = $PayloadKeys
      summary_mode = $SummaryMode
      summary_text = $SummaryText
      decision_mode = $DecisionMode
      hard_marker_found = [bool]$HardMarkerFound
      hard_marker_key = $HardMarkerKey
      hard_marker_value = $HardMarkerValue
      notify_sent = [bool]$NotifySent
      notify_reason = $NotifyReason
      is_success = [bool]$IsSuccess
      notify_duration_ms = 2500
      click_wait_ms = 8000
      locale = $LocaleValue
      dir = $DirValue
      legal_profile = $LegalProfileValue
      i18n_fallback_used = [bool]$I18nFallbackUsed
      message_key = $MessageKey
    }
    $contextDir = Join-Path $HOME '.codex\hooks\logs'
    if (-not (Test-Path -LiteralPath $contextDir)) {
      New-Item -ItemType Directory -Path $contextDir -Force | Out-Null
    }
    $contextPath = Join-Path $contextDir ("notify-click-context-{0}.json" -f [guid]::NewGuid().ToString('N'))
    $contextJson = $context | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($contextPath, $contextJson, [System.Text.UTF8Encoding]::new($false))

    $argList = @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', $clickScriptPath,
      '-ContextPath', $contextPath
    )
    Start-Process -FilePath 'pwsh.exe' -WindowStyle Hidden -ArgumentList $argList | Out-Null
    return [pscustomobject]@{
      Started = $true
      Error = $null
    }
  } catch {
    return [pscustomobject]@{
      Started = $false
      Error = Truncate-ErrorMessage ([string]$_.Exception.Message)
    }
  }
}

try {
  $localeInfo = Resolve-NotifierLocale -Locale $Locale
  $dirInfo = Resolve-NotifierDirection -Dir $Dir -Locale $localeInfo.locale
  $legalInfo = Resolve-NotifierLegalProfile -LegalProfile $LegalProfile
  $effectiveLocale = [string]$localeInfo.locale
  $effectiveDir = [string]$dirInfo.dir_effective
  $effectiveLegalProfile = [string]$legalInfo.legal_profile

  $raw = [Console]::In.ReadToEnd()
  $inputSource = 'stdin'
  if ([string]::IsNullOrWhiteSpace($raw) -and $args.Count -gt 0) {
    $jsonLikeArg = $args | Where-Object { $_ -match '^\s*[\{\[]' } | Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($jsonLikeArg)) {
      $raw = $jsonLikeArg
    } else {
      $raw = ($args -join ' ')
    }
    $inputSource = 'argv'
  }

  $parseOk = $false
  $payloadObj = $null
  if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
      $payloadObj = $raw | ConvertFrom-Json -ErrorAction Stop
      $parseOk = $true
    } catch {}
  }

  $eventType = $null
  $eventName = $null
  $threadId = $null
  $turnId = $null
  $rawPreview = ''
  $payloadKeys = @()
  if ($parseOk -and $payloadObj -ne $null) {
    $payloadKeys = @($payloadObj.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    if ($payloadObj.PSObject.Properties.Name -contains 'type') { $eventType = [string]$payloadObj.type }
    if ($payloadObj.PSObject.Properties.Name -contains 'event') { $eventName = [string]$payloadObj.event }
    if ($payloadObj.PSObject.Properties.Name -contains 'thread-id') { $threadId = [string]$payloadObj.'thread-id' }
    if ($payloadObj.PSObject.Properties.Name -contains 'turn-id') { $turnId = [string]$payloadObj.'turn-id' }

    $parts = New-Object System.Collections.Generic.List[string]
    if ($eventType) { $parts.Add("type=$eventType") }
    if ($eventName) { $parts.Add("event=$eventName") }
    if ($threadId) { $parts.Add("thread-id=$threadId") }
    if ($turnId) { $parts.Add("turn-id=$turnId") }
    if ($parts.Count -gt 0) {
      $rawPreview = $parts -join '; '
    } else {
      $rawPreview = 'parsed-json'
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($raw)) {
    $max = [Math]::Min($raw.Length, 160)
    $rawPreview = $raw.Substring(0, $max).Replace("`r", '\r').Replace("`n", '\n')
  }

  $isSuccess = (($eventType -eq 'agent-turn-complete') -or ($eventName -eq 'Stop'))

  $statusSuccessResult = Resolve-I18nTextSafe -Key 'notifications.status_success' -LocaleValue $effectiveLocale -DefaultText '✅'
  $statusFailResult = Resolve-I18nTextSafe -Key 'notifications.status_failure' -LocaleValue $effectiveLocale -DefaultText '❌'
  $statusGlyph = if ($isSuccess) { [string]$statusSuccessResult.text } else { [string]$statusFailResult.text }

  $titleTextResult = Resolve-I18nTextSafe -Key 'notifications.title_task_complete' -LocaleValue $effectiveLocale
  $title = ('{0} {1}' -f $statusGlyph, [string]$titleTextResult.text)

  $trimPrefixesInfo = Get-I18nListSafe -Key 'notifications.summary_trim_prefixes' -LocaleValue $effectiveLocale
  $trimPrefixes = @($trimPrefixesInfo.items)
  if ($trimPrefixes.Count -eq 0) {
    $trimPrefixes = @('summary:', 'Summary:')
  }

  $summary = New-RuleSummary `
    -Payload $payloadObj `
    -IsSuccess $isSuccess `
    -EventType $eventType `
    -EventName $eventName `
    -LocaleValue $effectiveLocale `
    -TrimPrefixes $trimPrefixes
  $summaryText = [string]$summary.Text
  $summaryMode = [string]$summary.Mode
  $messageKey = [string]$summary.MessageKey

  $hardMarker = Get-HardFinalMarker -Payload $payloadObj
  $mode = 'fallback_rules'
  $notifySent = $false
  $notifyReason = 'skip_unknown'
  if ($hardMarker.Found) {
    $mode = 'hard_marker'
    if (Test-Truthy $hardMarker.Value) {
      $notifySent = $true
      $notifyReason = 'notify_hard_marker_truthy'
    } else {
      $notifySent = $false
      $notifyReason = 'skip_hard_marker_falsey'
    }
  } else {
    $fallbackDecision = Test-ShouldNotifyWithFallback -ParseOk $parseOk -EventType $eventType -SummaryMode $summaryMode -ThreadId $threadId -SummaryText $summaryText
    $notifySent = [bool]$fallbackDecision.Notify
    $notifyReason = [string]$fallbackDecision.Reason
  }

  $timeValue = if (Get-Command -Name Format-I18nTime -ErrorAction SilentlyContinue) {
    Format-I18nTime -Value ([DateTimeOffset]::Now) -Locale $effectiveLocale
  } else {
    (Get-Date -Format 'T')
  }
  $timeLineResult = Resolve-I18nTextSafe -Key 'notifications.time_completed' -LocaleValue $effectiveLocale -ArgsObject @{ time = $timeValue }
  $bodyTemplateResult = Resolve-I18nTextSafe -Key 'notifications.body_template' -LocaleValue $effectiveLocale -ArgsObject @{
    status = $statusGlyph
    summary = $summaryText
    timeLine = [string]$timeLineResult.text
  } -DefaultText ('{0} {1}  {2}' -f $statusGlyph, $summaryText, [string]$timeLineResult.text)
  $body = [string]$bodyTemplateResult.text

  $maxElements = if (Get-Command -Name Get-I18nMaxTextElements -ErrorAction SilentlyContinue) {
    Get-I18nMaxTextElements -Locale $effectiveLocale -Default 180
  } else { 180 }
  if (Get-Command -Name Truncate-I18nText -ErrorAction SilentlyContinue) {
    $body = Truncate-I18nText -Text $body -MaxTextElements $maxElements
  } elseif ($body.Length -gt 180) {
    $body = $body.Substring(0, 180) + '...'
  }

  $fallbackFlags = @(
    [bool]$titleTextResult.fallback_used,
    [bool]$timeLineResult.fallback_used,
    [bool]$bodyTemplateResult.fallback_used,
    [bool]$summary.FallbackUsed,
    [bool]$trimPrefixesInfo.fallback_used,
    [bool]$statusSuccessResult.fallback_used,
    [bool]$statusFailResult.fallback_used
  )
  $i18nFallbackUsed = ($fallbackFlags | Where-Object { $_ } | Measure-Object).Count -gt 0

  $defaultCwdValue = Resolve-NotifierDefaultCwd -Configured $DefaultCwd
  $targetCwd = Resolve-TargetCwd -Payload $payloadObj -FallbackCwd $defaultCwdValue
  $workspaceToken = Split-Path -Path $targetCwd -Leaf
  $hardMarkerValueText = if ($null -eq $hardMarker.Value) { '' } else { [string]$hardMarker.Value }
  $clickEnabled = [bool]$notifySent
  $clickReceived = $false
  $jumpStrategy = 'none'
  $jumpWindowTitle = $null
  $jumpWindowPid = $null
  $jumpResult = 'failed'
  $jumpError = if ($notifySent) { 'click_pending' } else { 'click_disabled' }

  if ($notifySent) {
    $worker = Start-ClickNotifyWorker `
      -Title $title `
      -Body $body `
      -Cwd $targetCwd `
      -DefaultCwdValue $defaultCwdValue `
      -ThreadId $threadId `
      -TurnId $turnId `
      -EventType $eventType `
      -EventName $eventName `
      -InputSource $inputSource `
      -ParseOk $parseOk `
      -PayloadLen ([int]$raw.Length) `
      -RawPreview $rawPreview `
      -PayloadKeys ($payloadKeys -join '|') `
      -SummaryMode $summaryMode `
      -SummaryText $summaryText `
      -DecisionMode $mode `
      -HardMarkerFound ([bool]$hardMarker.Found) `
      -HardMarkerKey ([string]$hardMarker.Key) `
      -HardMarkerValue $hardMarkerValueText `
      -NotifySent $notifySent `
      -NotifyReason $notifyReason `
      -IsSuccess $isSuccess `
      -LocaleValue $effectiveLocale `
      -DirValue $effectiveDir `
      -LegalProfileValue $effectiveLegalProfile `
      -I18nFallbackUsed $i18nFallbackUsed `
      -MessageKey $messageKey

    if ($worker.Started) {
      return
    }

    $notifySent = $false
    $notifyReason = 'notify_worker_start_failed'
    $clickEnabled = $false
    $jumpError = if ([string]::IsNullOrWhiteSpace([string]$worker.Error)) { 'notify_worker_start_failed' } else { [string]$worker.Error }
    [void](Show-DirectBalloon -Title $title -Body $body -IsSuccess $isSuccess)
  }

  try {
    $logDir = Join-Path $HOME '.codex\hooks\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
      New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logPath = Join-Path $logDir 'notify-stop-events.jsonl'

    $record = [ordered]@{
      schema_version = 3
      ts_iso = [DateTimeOffset]::Now.ToString('o')
      source = $inputSource
      parse_ok = [bool]$parseOk
      payload_len = [int]$raw.Length
      event_type = $eventType
      event_name = $eventName
      thread_id = $threadId
      turn_id = $turnId
      raw_preview = $rawPreview
      payload_keys = ($payloadKeys -join '|')
      summary_mode = $summaryMode
      summary_text = $summaryText
      decision_mode = $mode
      hard_marker_found = [bool]$hardMarker.Found
      hard_marker_key = [string]$hardMarker.Key
      hard_marker_value = if ($null -eq $hardMarker.Value) { $null } else { [string]$hardMarker.Value }
      notify_sent = [bool]$notifySent
      notify_reason = $notifyReason
      click_enabled = [bool]$clickEnabled
      click_received = [bool]$clickReceived
      jump_strategy = $jumpStrategy
      jump_target_cwd = $targetCwd
      jump_workspace_token = $workspaceToken
      jump_window_title = $jumpWindowTitle
      jump_window_pid = $jumpWindowPid
      jump_result = $jumpResult
      jump_error = Truncate-ErrorMessage $jumpError
      locale = $effectiveLocale
      dir = $effectiveDir
      legal_profile = $effectiveLegalProfile
      i18n_fallback_used = [bool]$i18nFallbackUsed
      message_key = $messageKey
    }
    $line = $record | ConvertTo-Json -Compress
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
  } catch {}
} catch {
  # Swallow all errors to avoid impacting Codex flow.
} finally {
  exit 0
}
