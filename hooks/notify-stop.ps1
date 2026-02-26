param(
  [string]$DefaultCwd = ''
)

$ErrorActionPreference = 'Stop'

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

function Convert-CodePointsToString {
  param([int[]]$Codes)
  return -join ($Codes | ForEach-Object { [char]$_ })
}

function Normalize-OneLine {
  param([string]$Text, [int]$MaxLen = 72)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $oneLine = $Text -replace '[\r\n\t]+', ' '
  $oneLine = $oneLine -replace '\s{2,}', ' '
  $oneLine = $oneLine.Trim()
  $oneLine = $oneLine.TrimStart('#', '-', '*', '`', '>', ' ')
  while ($oneLine -match '^(?:总结|摘要|summary)\s*[:：]\s*') {
    $oneLine = $oneLine -replace '^(?:总结|摘要|summary)\s*[:：]\s*', ''
    $oneLine = $oneLine.Trim()
  }
  if ($oneLine.Length -gt $MaxLen) {
    $oneLine = $oneLine.Substring(0, $MaxLen) + '...'
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
    [string]$EventName
  )

  $defaultSuccess = Convert-CodePointsToString @(24050,23436,25104,26412,36718,20219,21153,65292,32467,26524,24050,36820,22238,12290)
  $defaultStop = Convert-CodePointsToString @(20219,21153,24050,32467,26463,12290)
  $defaultUnknown = Convert-CodePointsToString @(20219,21153,29366,24577,24050,26356,26032,12290)

  $assistantLine = $null
  $inputLine = $null

  if ($null -ne $Payload) {
    $assistantProp = $Payload.PSObject.Properties['last-assistant-message']
    if ($null -ne $assistantProp) {
      $assistantRaw = Get-MessageLikeText $assistantProp.Value
      $assistantLine = Normalize-OneLine (Get-FirstContentLine $assistantRaw)
    }

    $inputProp = $Payload.PSObject.Properties['input-messages']
    if ($null -ne $inputProp) {
      $inputRaw = Get-MessageLikeText $inputProp.Value
      $inputLine = Normalize-OneLine (Get-FirstContentLine $inputRaw)
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($assistantLine)) {
    return [pscustomobject]@{ Text = $assistantLine; Mode = 'assistant' }
  }
  if (-not [string]::IsNullOrWhiteSpace($inputLine)) {
    return [pscustomobject]@{ Text = $inputLine; Mode = 'input' }
  }
  if ($EventType -eq 'agent-turn-complete' -or $IsSuccess) {
    return [pscustomobject]@{ Text = $defaultSuccess; Mode = 'fallback_success' }
  }
  if ($EventName -eq 'Stop') {
    return [pscustomobject]@{ Text = $defaultStop; Mode = 'fallback_stop' }
  }
  return [pscustomobject]@{ Text = $defaultUnknown; Mode = 'fallback_unknown' }
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
  # Filter obvious in-progress/status payloads (JSON cards, headings, list fragments)
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
    [string]$DefaultCwd
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
  return $DefaultCwd
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
    } else {
      $notifyIcon.Icon = [System.Drawing.SystemIcons]::Error
    }
    $notifyIcon.Visible = $true
    $notifyIcon.BalloonTipTitle = $Title
    $notifyIcon.BalloonTipText = $Body
    if ($IsSuccess) {
      $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    } else {
      $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
    }
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
    [string]$DefaultCwd,
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
    [bool]$IsSuccess
  )

  $clickScriptPath = Join-Path $HOME '.codex\hooks\notify-click-jump.ps1'
  if (-not (Test-Path -LiteralPath $clickScriptPath)) {
    return [pscustomobject]@{
      Started = $false
      Error = "click script missing: $clickScriptPath"
    }
  }

  try {
    $context = [ordered]@{
      title = $Title
      body = $Body
      cwd = $Cwd
      default_cwd = $DefaultCwd
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
    }
    $contextPath = Join-Path $HOME (".codex\hooks\logs\notify-click-context-{0}.json" -f [guid]::NewGuid().ToString('N'))
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

  try {
    $logDir = Join-Path $HOME '.codex\hooks\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
      New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logPath = Join-Path $logDir 'notify-stop-events.jsonl'

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

  } catch {}

  $baseTitle = Convert-CodePointsToString @(67,111,100,101,120,32,24050,23436,25104,24403,21069,20219,21153)
  $timePrefix = Convert-CodePointsToString @(23436,25104,26102,38388,32)
  $isSuccess = $false
  if (($eventType -eq 'agent-turn-complete') -or ($eventName -eq 'Stop')) {
    $isSuccess = $true
  }
  $statusSuccess = Convert-CodePointsToString @(9989) # ✅
  $statusFail = Convert-CodePointsToString @(10060)   # ❌
  $statusGlyph = if ($isSuccess) { $statusSuccess } else { $statusFail }
  $title = ('{0} {1}' -f $statusGlyph, $baseTitle)
  $summary = New-RuleSummary -Payload $payloadObj -IsSuccess $isSuccess -EventType $eventType -EventName $eventName
  $summaryText = [string]$summary.Text
  $summaryMode = [string]$summary.Mode
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
  $body = ('{0} {1}  {2}{3}' -f $statusGlyph, $summaryText, $timePrefix, (Get-Date -Format 'HH:mm:ss'))
  if ($body.Length -gt 180) {
    $body = $body.Substring(0, 180) + '...'
  }

  $defaultCwd = Resolve-NotifierDefaultCwd -Configured $DefaultCwd
  $targetCwd = Resolve-TargetCwd -Payload $payloadObj -DefaultCwd $defaultCwd
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
      -DefaultCwd $defaultCwd `
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
      -IsSuccess $isSuccess

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
    if (Test-Path -LiteralPath $logPath) {
      $record = [ordered]@{
        schema_version = 2
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
      }
      $line = $record | ConvertTo-Json -Compress
      Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    }
  } catch {}
} catch {
  # swallow all errors to avoid impacting Codex flow
} finally {
  exit 0
}
