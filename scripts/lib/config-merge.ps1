Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-TomlBasicString {
  param([Parameter(Mandatory = $true)][string]$Value)

  $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
  return '"' + $escaped + '"'
}

function Get-ManagedStopHookBlock {
  param(
    [Parameter(Mandatory = $true)][string]$StopHookScriptPath,
    [Parameter(Mandatory = $true)][string]$DefaultCwd,
    [int]$TimeoutMs = 4000,
    [string]$Locale = 'auto',
    [string]$Dir = 'auto',
    [string]$LegalProfile = 'global-minimal'
  )

  $stopHookPathToml = ConvertTo-TomlBasicString -Value $StopHookScriptPath
  $defaultCwdToml = ConvertTo-TomlBasicString -Value $DefaultCwd
  $localeToml = ConvertTo-TomlBasicString -Value $Locale
  $dirToml = ConvertTo-TomlBasicString -Value $Dir
  $legalProfileToml = ConvertTo-TomlBasicString -Value $LegalProfile

  return @"
# codex-notifier managed block start
Stop = [
  { hooks = [
      { type = "command", command = ["pwsh.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $stopHookPathToml, "-DefaultCwd", $defaultCwdToml, "-Locale", $localeToml, "-Dir", $dirToml, "-LegalProfile", $legalProfileToml], timeout_ms = $TimeoutMs }
    ]
  }
]
# codex-notifier managed block end
"@.TrimEnd()
}

function Get-LineEnding {
  param([string]$Text)

  if ($Text -match "`r`n") {
    return "`r`n"
  }
  return "`n"
}

function Join-Lines {
  param(
    [string[]]$Lines,
    [string]$LineEnding
  )

  if ($Lines.Count -eq 0) {
    return ''
  }
  return [string]::Join($LineEnding, $Lines)
}

function Merge-CodexNotifierStopHook {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ConfigText,
    [Parameter(Mandatory = $true)][string]$StopHookScriptPath,
    [Parameter(Mandatory = $true)][string]$DefaultCwd,
    [int]$TimeoutMs = 4000,
    [string]$Locale = 'auto',
    [string]$Dir = 'auto',
    [string]$LegalProfile = 'global-minimal'
  )

  $lineEnding = Get-LineEnding -Text $ConfigText
  $normalized = $ConfigText.Replace("`r`n", "`n")
  $managedBlock = Get-ManagedStopHookBlock `
    -StopHookScriptPath $StopHookScriptPath `
    -DefaultCwd $DefaultCwd `
    -TimeoutMs $TimeoutMs `
    -Locale $Locale `
    -Dir $Dir `
    -LegalProfile $LegalProfile
  [string[]]$managedLines = $managedBlock.Split("`n")
  $lines = if ([string]::IsNullOrEmpty($normalized)) { @() } else { @($normalized.Split("`n")) }
  $mutable = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    [void]$mutable.Add($line)
  }

  $managedStart = '# codex-notifier managed block start'
  $managedEnd = '# codex-notifier managed block end'
  $startIndex = -1
  $endIndex = -1
  for ($i = 0; $i -lt $mutable.Count; $i++) {
    if ($mutable[$i].Trim() -eq $managedStart) {
      $startIndex = $i
      break
    }
  }
  if ($startIndex -ge 0) {
    for ($i = $startIndex + 1; $i -lt $mutable.Count; $i++) {
      if ($mutable[$i].Trim() -eq $managedEnd) {
        $endIndex = $i
        break
      }
    }
  }

  if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
    $removeCount = $endIndex - $startIndex + 1
    $mutable.RemoveRange($startIndex, $removeCount)
    $mutable.InsertRange($startIndex, [string[]]$managedLines)
    $newText = Join-Lines -Lines $mutable.ToArray() -LineEnding $lineEnding
    return [pscustomobject]@{
      status = 'updated'
      changed = ($newText -ne $ConfigText)
      conflict = $false
      new_text = $newText
    }
  }

  $hooksIndex = -1
  for ($i = 0; $i -lt $mutable.Count; $i++) {
    if ($mutable[$i].Trim() -eq '[hooks]') {
      $hooksIndex = $i
      break
    }
  }

  if ($hooksIndex -lt 0) {
    if ($mutable.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($mutable[$mutable.Count - 1])) {
      [void]$mutable.Add('')
    }
    [void]$mutable.Add('[hooks]')
    foreach ($managedLine in $managedLines) {
      [void]$mutable.Add([string]$managedLine)
    }
    $newText = Join-Lines -Lines $mutable.ToArray() -LineEnding $lineEnding
    return [pscustomobject]@{
      status = 'updated'
      changed = ($newText -ne $ConfigText)
      conflict = $false
      new_text = $newText
    }
  }

  $nextSectionIndex = $mutable.Count
  for ($i = $hooksIndex + 1; $i -lt $mutable.Count; $i++) {
    $trimmed = $mutable[$i].Trim()
    if ($trimmed -match '^\[[^]]+\]$') {
      $nextSectionIndex = $i
      break
    }
  }

  for ($i = $hooksIndex + 1; $i -lt $nextSectionIndex; $i++) {
    $trimmed = $mutable[$i].TrimStart()
    if ($trimmed.StartsWith('#')) {
      continue
    }
    if ($trimmed -match '^Stop\s*=') {
      return [pscustomobject]@{
        status = 'conflict_manual_merge_required'
        changed = $false
        conflict = $true
        new_text = $ConfigText
      }
    }
  }

  $insertIndex = $hooksIndex + 1
  if ($insertIndex -lt $mutable.Count -and -not [string]::IsNullOrWhiteSpace($mutable[$insertIndex])) {
    [string[]]$managedLines = @('') + $managedLines
  }
  $mutable.InsertRange($insertIndex, [string[]]$managedLines)
  $newText = Join-Lines -Lines $mutable.ToArray() -LineEnding $lineEnding
  return [pscustomobject]@{
    status = 'updated'
    changed = ($newText -ne $ConfigText)
    conflict = $false
    new_text = $newText
  }
}
