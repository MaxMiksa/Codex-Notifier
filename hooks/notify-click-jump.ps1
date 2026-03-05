param(
  [string]$ContextPath = '',
  [string]$Title = '',
  [string]$Body = '',
  [string]$Cwd = '',
  [string]$DefaultCwd = '',
  [string]$ThreadId = '',
  [string]$TurnId = '',
  [string]$EventType = '',
  [string]$EventName = '',
  [string]$InputSource = '',
  [string]$ParseOk = 'false',
  [string]$PayloadLen = '0',
  [string]$RawPreview = '',
  [string]$PayloadKeys = '',
  [string]$SummaryMode = '',
  [string]$SummaryText = '',
  [string]$DecisionMode = '',
  [string]$HardMarkerFound = 'false',
  [string]$HardMarkerKey = '',
  [string]$HardMarkerValue = '',
  [string]$NotifySent = 'true',
  [string]$NotifyReason = '',
  [string]$IsSuccess = 'true',
  [string]$NotifyDurationMs = '2500',
  [string]$ClickWaitMs = '8000',
  [string]$Locale = 'auto',
  [string]$Dir = 'auto',
  [string]$LegalProfile = 'global-minimal',
  [string]$I18nFallbackUsed = 'false',
  [string]$MessageKey = '',
  [string]$ClientOriginator = '',
  [string]$ClientSource = '',
  [string]$ClientOriginatorField = '',
  [string]$ClientSourceField = '',
  [string]$ClientAllowlisted = 'false'
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

foreach ($libName in @('locale-resolver.ps1', 'layout-direction.ps1')) {
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

function Get-ContextString {
  param(
    [object]$Context,
    [string]$Name,
    [string]$Default = ''
  )
  if ($null -eq $Context) { return $Default }
  $prop = $Context.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  if ($null -eq $prop.Value) { return $Default }
  return [string]$prop.Value
}

function Get-ContextRaw {
  param(
    [object]$Context,
    [string]$Name
  )
  if ($null -eq $Context) { return $null }
  $prop = $Context.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Convert-ToBool {
  param($Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return [bool]$Value }
  $text = ([string]$Value).Trim().ToLowerInvariant()
  return @('1', 'true', 'yes', 'y', 'done', 'final') -contains $text
}

function Convert-ToInt {
  param($Value, [int]$Default = 0)
  $number = 0
  if ([int]::TryParse([string]$Value, [ref]$number)) {
    return $number
  }
  return $Default
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

function Truncate-ErrorMessage {
  param([string]$Message, [int]$MaxLen = 240)
  if ([string]::IsNullOrWhiteSpace($Message)) { return $null }
  $oneLine = ($Message -replace '[\r\n\t]+', ' ').Trim()
  if ($oneLine.Length -gt $MaxLen) {
    return $oneLine.Substring(0, $MaxLen) + '...'
  }
  return $oneLine
}

function Resolve-TargetCwd {
  param(
    [string]$Candidate,
    [string]$Fallback
  )
  if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path -LiteralPath $Candidate)) {
    return $Candidate
  }
  return $Fallback
}

function Normalize-PathForCompare {
  param([string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }
  try {
    return [System.IO.Path]::GetFullPath($PathValue).TrimEnd('\').ToLowerInvariant()
  } catch {
    return $PathValue.Trim().TrimEnd('\').ToLowerInvariant()
  }
}

function Ensure-NativeWindowApi {
  if (([System.Management.Automation.PSTypeName]'CodexWindowApi').Type) {
    return
  }

  Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class CodexWindowApi
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int processId);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
}

function Get-TopCodeWindowByWorkspaceToken {
  param([string]$WorkspaceToken)

  Ensure-NativeWindowApi
  $suffix = " - $WorkspaceToken - Visual Studio Code"
  $script:windowMatches = New-Object System.Collections.Generic.List[object]

  $callback = [CodexWindowApi+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    try {
      if (-not [CodexWindowApi]::IsWindowVisible($hWnd)) { return $true }
      $len = [CodexWindowApi]::GetWindowTextLength($hWnd)
      if ($len -le 0) { return $true }

      $sb = New-Object System.Text.StringBuilder ($len + 1)
      [void][CodexWindowApi]::GetWindowText($hWnd, $sb, $sb.Capacity)
      $title = $sb.ToString()
      if ([string]::IsNullOrWhiteSpace($title)) { return $true }
      if (-not $title.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

      $procId = 0
      [void][CodexWindowApi]::GetWindowThreadProcessId($hWnd, [ref]$procId)
      if ($procId -le 0) { return $true }

      $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
      if ($null -eq $proc) { return $true }
      if ($proc.ProcessName -ine 'Code') { return $true }

      $script:windowMatches.Add([pscustomobject]@{
        Handle = $hWnd
        Pid = [int]$procId
        Title = $title
      })
    } catch {}
    return $true
  }

  [void][CodexWindowApi]::EnumWindows($callback, [IntPtr]::Zero)
  if ($script:windowMatches.Count -gt 0) {
    return $script:windowMatches[0]
  }
  return $null
}

function Get-TopCodeWindowAny {
  param([IntPtr]$ExcludeHandle = [IntPtr]::Zero)

  Ensure-NativeWindowApi
  $script:anyCodeWindows = New-Object System.Collections.Generic.List[object]

  $callback = [CodexWindowApi+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    try {
      if ($hWnd -eq $ExcludeHandle) { return $true }
      if (-not [CodexWindowApi]::IsWindowVisible($hWnd)) { return $true }
      $len = [CodexWindowApi]::GetWindowTextLength($hWnd)
      if ($len -le 0) { return $true }

      $sb = New-Object System.Text.StringBuilder ($len + 1)
      [void][CodexWindowApi]::GetWindowText($hWnd, $sb, $sb.Capacity)
      $title = $sb.ToString()
      if ([string]::IsNullOrWhiteSpace($title)) { return $true }
      if (-not $title.EndsWith(' - Visual Studio Code', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

      $procId = 0
      [void][CodexWindowApi]::GetWindowThreadProcessId($hWnd, [ref]$procId)
      if ($procId -le 0) { return $true }

      $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
      if ($null -eq $proc) { return $true }
      if ($proc.ProcessName -ine 'Code') { return $true }

      $script:anyCodeWindows.Add([pscustomobject]@{
        Handle = $hWnd
        Pid = [int]$procId
        Title = $title
      })
    } catch {}
    return $true
  }

  [void][CodexWindowApi]::EnumWindows($callback, [IntPtr]::Zero)
  if ($script:anyCodeWindows.Count -gt 0) {
    return $script:anyCodeWindows[0]
  }
  return $null
}

function Try-ActivateWindow {
  param([IntPtr]$Handle)
  try {
    if ([CodexWindowApi]::IsIconic($Handle)) {
      [void][CodexWindowApi]::ShowWindowAsync($Handle, 9)
      Start-Sleep -Milliseconds 80
    }
    return [CodexWindowApi]::SetForegroundWindow($Handle)
  } catch {
    return $false
  }
}

function Invoke-CodeReuseWindow {
  param([string]$TargetCwd)
  try {
    Start-Process -FilePath 'code' -ArgumentList @('-r', $TargetCwd) -WindowStyle Hidden | Out-Null
    return [pscustomobject]@{
      Ok = $true
      Error = $null
    }
  } catch {
    return [pscustomobject]@{
      Ok = $false
      Error = Truncate-ErrorMessage ([string]$_.Exception.Message)
    }
  }
}

try {
  if (-not [string]::IsNullOrWhiteSpace($ContextPath) -and (Test-Path -LiteralPath $ContextPath)) {
    $ctx = $null
    try {
      $ctxRaw = Get-Content -Raw -LiteralPath $ContextPath
      if (-not [string]::IsNullOrWhiteSpace($ctxRaw)) {
        $ctx = $ctxRaw | ConvertFrom-Json
      }
    } catch {}
    try { Remove-Item -LiteralPath $ContextPath -Force -ErrorAction SilentlyContinue } catch {}

    if ($null -ne $ctx) {
      $Title = Get-ContextString -Context $ctx -Name 'title' -Default $Title
      $Body = Get-ContextString -Context $ctx -Name 'body' -Default $Body
      $Cwd = Get-ContextString -Context $ctx -Name 'cwd' -Default $Cwd
      $DefaultCwd = Get-ContextString -Context $ctx -Name 'default_cwd' -Default $DefaultCwd
      $ThreadId = Get-ContextString -Context $ctx -Name 'thread_id' -Default $ThreadId
      $TurnId = Get-ContextString -Context $ctx -Name 'turn_id' -Default $TurnId
      $EventType = Get-ContextString -Context $ctx -Name 'event_type' -Default $EventType
      $EventName = Get-ContextString -Context $ctx -Name 'event_name' -Default $EventName
      $InputSource = Get-ContextString -Context $ctx -Name 'input_source' -Default $InputSource
      $ParseOk = [string](Get-ContextRaw -Context $ctx -Name 'parse_ok')
      $PayloadLen = [string](Get-ContextRaw -Context $ctx -Name 'payload_len')
      $RawPreview = Get-ContextString -Context $ctx -Name 'raw_preview' -Default $RawPreview
      $PayloadKeys = Get-ContextString -Context $ctx -Name 'payload_keys' -Default $PayloadKeys
      $SummaryMode = Get-ContextString -Context $ctx -Name 'summary_mode' -Default $SummaryMode
      $SummaryText = Get-ContextString -Context $ctx -Name 'summary_text' -Default $SummaryText
      $DecisionMode = Get-ContextString -Context $ctx -Name 'decision_mode' -Default $DecisionMode
      $HardMarkerFound = [string](Get-ContextRaw -Context $ctx -Name 'hard_marker_found')
      $HardMarkerKey = Get-ContextString -Context $ctx -Name 'hard_marker_key' -Default $HardMarkerKey
      $HardMarkerValue = Get-ContextString -Context $ctx -Name 'hard_marker_value' -Default $HardMarkerValue
      $NotifySent = [string](Get-ContextRaw -Context $ctx -Name 'notify_sent')
      $NotifyReason = Get-ContextString -Context $ctx -Name 'notify_reason' -Default $NotifyReason
      $IsSuccess = [string](Get-ContextRaw -Context $ctx -Name 'is_success')
      $NotifyDurationMs = [string](Get-ContextRaw -Context $ctx -Name 'notify_duration_ms')
      $ClickWaitMs = [string](Get-ContextRaw -Context $ctx -Name 'click_wait_ms')
      $Locale = Get-ContextString -Context $ctx -Name 'locale' -Default $Locale
      $Dir = Get-ContextString -Context $ctx -Name 'dir' -Default $Dir
      $LegalProfile = Get-ContextString -Context $ctx -Name 'legal_profile' -Default $LegalProfile
      $I18nFallbackUsed = [string](Get-ContextRaw -Context $ctx -Name 'i18n_fallback_used')
      $MessageKey = Get-ContextString -Context $ctx -Name 'message_key' -Default $MessageKey
      $ClientOriginator = Get-ContextString -Context $ctx -Name 'client_originator' -Default $ClientOriginator
      $ClientSource = Get-ContextString -Context $ctx -Name 'client_source' -Default $ClientSource
      $ClientOriginatorField = Get-ContextString -Context $ctx -Name 'client_originator_field' -Default $ClientOriginatorField
      $ClientSourceField = Get-ContextString -Context $ctx -Name 'client_source_field' -Default $ClientSourceField
      $ClientAllowlisted = [string](Get-ContextRaw -Context $ctx -Name 'client_allowlisted')
    }
  }

  $parseOkBool = Convert-ToBool $ParseOk
  $payloadLenInt = Convert-ToInt $PayloadLen 0
  $hardMarkerFoundBool = Convert-ToBool $HardMarkerFound
  $notifySentBool = Convert-ToBool $NotifySent
  $isSuccessBool = Convert-ToBool $IsSuccess
  $notifyDuration = Convert-ToInt $NotifyDurationMs 2500
  $clickWait = Convert-ToInt $ClickWaitMs 8000
  $i18nFallbackUsedBool = Convert-ToBool $I18nFallbackUsed
  $clientAllowlistedBool = Convert-ToBool $ClientAllowlisted

  $localeInfo = Resolve-NotifierLocale -Locale $Locale
  $dirInfo = Resolve-NotifierDirection -Dir $Dir -Locale $localeInfo.locale
  $legalInfo = Resolve-NotifierLegalProfile -LegalProfile $LegalProfile
  $effectiveLocale = [string]$localeInfo.locale
  $effectiveDir = [string]$dirInfo.dir_effective
  $effectiveLegalProfile = [string]$legalInfo.legal_profile

  $DefaultCwd = Resolve-NotifierDefaultCwd -Configured $DefaultCwd
  $targetCwd = Resolve-TargetCwd -Candidate $Cwd -Fallback $DefaultCwd
  $workspaceToken = Split-Path -Path $targetCwd -Leaf

  $clickEnabled = $true
  $clickReceived = $false
  $balloonShown = $false
  $showAttempts = 0
  $jumpStrategy = 'none'
  $jumpWindowTitle = $null
  $jumpWindowPid = $null
  $jumpResult = 'failed'
  $jumpError = 'click_not_received'

  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    if ($isSuccessBool) {
      $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
      $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    } else {
      $notifyIcon.Icon = [System.Drawing.SystemIcons]::Error
      $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
    }
    $notifyIcon.Visible = $true
    $notifyIcon.BalloonTipTitle = $Title
    $notifyIcon.BalloonTipText = $Body

    $script:clicked = $false
    $script:clickSource = 'none'
    $script:balloonShown = $false
    $script:minClickAt = [DateTime]::UtcNow.AddMilliseconds(400)
    $notifyIcon.add_BalloonTipShown({
      Set-Variable -Name balloonShown -Value $true -Scope Script
    })
    $notifyIcon.add_BalloonTipClicked({
      if ([DateTime]::UtcNow -lt $script:minClickAt) { return }
      Set-Variable -Name clicked -Value $true -Scope Script
      Set-Variable -Name clickSource -Value 'balloon' -Scope Script
    })
    $notifyIcon.add_Click({
      if ([DateTime]::UtcNow -lt $script:minClickAt) { return }
      Set-Variable -Name clicked -Value $true -Scope Script
      if ($script:clickSource -eq 'none') {
        Set-Variable -Name clickSource -Value 'tray' -Scope Script
      }
    })

    $showAttempts = 1
    $notifyIcon.ShowBalloonTip($notifyDuration)

    $shownDeadline = [DateTime]::UtcNow.AddMilliseconds(900)
    while ([DateTime]::UtcNow -lt $shownDeadline -and -not $script:balloonShown) {
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 50
    }
    if (-not $script:balloonShown) {
      Start-Sleep -Milliseconds 120
      $showAttempts = 2
      $notifyIcon.ShowBalloonTip($notifyDuration)
      $shownDeadline2 = [DateTime]::UtcNow.AddMilliseconds(900)
      while ([DateTime]::UtcNow -lt $shownDeadline2 -and -not $script:balloonShown) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
      }
    }
    $balloonShown = [bool]$script:balloonShown

    $deadline = [DateTime]::UtcNow.AddMilliseconds($clickWait)
    while ([DateTime]::UtcNow -lt $deadline -and -not $script:clicked) {
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 50
    }

    $clickReceived = [bool]$script:clicked
    $notifyIcon.Dispose()
  } catch {
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    Write-Host "$Title - $Body"
    $clickReceived = $false
    $balloonShown = $false
    $jumpError = Truncate-ErrorMessage ([string]$_.Exception.Message)
  }

  if ($clickReceived) {
    try {
      $fallbackReason = $null
      $match = $null
      $activated = $false
      $targetNorm = Normalize-PathForCompare $targetCwd
      $defaultNorm = Normalize-PathForCompare $DefaultCwd
      $preferAnyFirst = (-not [string]::IsNullOrWhiteSpace($targetNorm)) -and ($targetNorm -eq $defaultNorm)

      if ($preferAnyFirst) {
        $anyFirstMatch = Get-TopCodeWindowAny
        if ($null -ne $anyFirstMatch) {
          $jumpStrategy = 'window-any'
          $jumpWindowTitle = [string]$anyFirstMatch.Title
          $jumpWindowPid = [int]$anyFirstMatch.Pid
          $activated = Try-ActivateWindow -Handle $anyFirstMatch.Handle
          if ($activated) {
            $jumpResult = 'ok'
            $jumpError = $null
          } else {
            $fallbackReason = 'window_any_activate_failed'
          }
        } else {
          $fallbackReason = 'window_any_not_found'
        }
      }

      if (-not $activated) {
        if (-not [string]::IsNullOrWhiteSpace($workspaceToken)) {
          $match = Get-TopCodeWindowByWorkspaceToken -WorkspaceToken $workspaceToken
        }

        if ($null -ne $match) {
          $jumpStrategy = 'window-title'
          $jumpWindowTitle = [string]$match.Title
          $jumpWindowPid = [int]$match.Pid
          $activated = Try-ActivateWindow -Handle $match.Handle
          if ($activated) {
            $jumpResult = 'ok'
            $jumpError = $null
          } elseif ([string]::IsNullOrWhiteSpace($fallbackReason)) {
            $fallbackReason = 'window_title_activate_failed'
          }
        } elseif ([string]::IsNullOrWhiteSpace($fallbackReason)) {
          $fallbackReason = 'window_title_not_found'
        }
      }

      if (-not $activated -and -not $preferAnyFirst) {
        $excludeHandle = [IntPtr]::Zero
        if ($null -ne $match) {
          $excludeHandle = $match.Handle
        }
        $anyMatch = Get-TopCodeWindowAny -ExcludeHandle $excludeHandle
        if ($null -ne $anyMatch) {
          $jumpStrategy = 'window-any'
          $jumpWindowTitle = [string]$anyMatch.Title
          $jumpWindowPid = [int]$anyMatch.Pid
          $activated = Try-ActivateWindow -Handle $anyMatch.Handle
          if ($activated) {
            $jumpResult = 'ok'
            $jumpError = $null
          } elseif ([string]::IsNullOrWhiteSpace($fallbackReason)) {
            $fallbackReason = 'window_any_activate_failed'
          }
        } elseif ([string]::IsNullOrWhiteSpace($fallbackReason)) {
          $fallbackReason = 'window_any_not_found'
        }
      }

      if (-not $activated) {
        $fallback = Invoke-CodeReuseWindow -TargetCwd $targetCwd
        $jumpStrategy = 'code-reuse-window'
        if ($fallback.Ok) {
          $jumpResult = 'fallback'
          $jumpError = if ([string]::IsNullOrWhiteSpace($fallbackReason)) { $null } else { $fallbackReason }
        } else {
          $jumpResult = 'failed'
          if ([string]::IsNullOrWhiteSpace([string]$fallback.Error)) {
            $jumpError = if ([string]::IsNullOrWhiteSpace($fallbackReason)) { 'fallback_launch_failed' } else { $fallbackReason }
          } else {
            $jumpError = [string]$fallback.Error
          }
        }
      }
    } catch {
      $jumpStrategy = 'none'
      $jumpResult = 'failed'
      $jumpError = Truncate-ErrorMessage ([string]$_.Exception.Message)
    }
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
      source = $InputSource
      parse_ok = [bool]$parseOkBool
      payload_len = [int]$payloadLenInt
      event_type = $EventType
      event_name = $EventName
      thread_id = $ThreadId
      turn_id = $TurnId
      raw_preview = $RawPreview
      payload_keys = $PayloadKeys
      summary_mode = $SummaryMode
      summary_text = $SummaryText
      decision_mode = $DecisionMode
      hard_marker_found = [bool]$hardMarkerFoundBool
      hard_marker_key = $HardMarkerKey
      hard_marker_value = if ([string]::IsNullOrWhiteSpace($HardMarkerValue)) { $null } else { $HardMarkerValue }
      notify_sent = [bool]$notifySentBool
      notify_reason = $NotifyReason
      click_enabled = [bool]$clickEnabled
      click_received = [bool]$clickReceived
      balloon_shown = [bool]$balloonShown
      show_attempts = [int]$showAttempts
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
      i18n_fallback_used = [bool]$i18nFallbackUsedBool
      message_key = $MessageKey
      client_originator = if ([string]::IsNullOrWhiteSpace($ClientOriginator)) { $null } else { $ClientOriginator }
      client_source = if ([string]::IsNullOrWhiteSpace($ClientSource)) { $null } else { $ClientSource }
      client_originator_field = if ([string]::IsNullOrWhiteSpace($ClientOriginatorField)) { $null } else { $ClientOriginatorField }
      client_source_field = if ([string]::IsNullOrWhiteSpace($ClientSourceField)) { $null } else { $ClientSourceField }
      client_allowlisted = [bool]$clientAllowlistedBool
    }
    $line = $record | ConvertTo-Json -Compress
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
  } catch {}
} catch {
  # Swallow all errors to avoid impacting Codex flow.
} finally {
  exit 0
}
