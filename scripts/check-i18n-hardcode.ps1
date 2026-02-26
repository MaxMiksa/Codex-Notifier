[CmdletBinding()]
param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scanDirs = @(
  (Join-Path $RepoRoot 'hooks'),
  (Join-Path $RepoRoot 'scripts')
)

$files = @()
foreach ($dir in $scanDirs) {
  if (Test-Path -LiteralPath $dir) {
    $files += Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.ps1'
  }
}

$violations = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
  if ($file.FullName -like '*\scripts\lib\*') {
    continue
  }
  if ($file.Name -ieq 'check-i18n-hardcode.ps1') {
    continue
  }
  $lineNo = 0
  foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
    $lineNo++
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith('#')) { continue }

    $reason = $null
    if ($line -match '[\u4e00-\u9fff]') {
      $reason = 'cjk_literal'
    } elseif ($line -match 'BalloonTipTitle\s*=\s*["'']') {
      $reason = 'balloon_title_literal'
    } elseif ($line -match 'BalloonTipText\s*=\s*["'']') {
      $reason = 'balloon_text_literal'
    } elseif ($line -match 'Write-Host\s+["'']([^"'']+)["'']') {
      $content = [string]$matches[1]
      $contentNoVars = ($content -replace '\$[A-Za-z_][A-Za-z0-9_]*', '') -replace '[-:\s\{\}\(\)\[\]]', ''
      if ($contentNoVars -match '[A-Za-z\u4e00-\u9fff]') {
        $reason = 'write_host_literal'
      }
    } elseif ($line -match 'throw\s+["'']') {
      $reason = 'throw_literal'
    } elseif ($line -match 'Convert-CodePointsToString') {
      $reason = 'legacy_codepoint_text'
    }

    if ($null -ne $reason) {
      $violations.Add([pscustomobject]@{
          file = $file.FullName
          line = $lineNo
          reason = $reason
          content = $trimmed
        })
    }
  }
}

if ($violations.Count -gt 0) {
  Write-Output "I18N_HARDCODE_CHECK_FAILED"
  foreach ($v in $violations) {
    Write-Output ("{0}:{1} [{2}] {3}" -f $v.file, $v.line, $v.reason, $v.content)
  }
  exit 1
}

Write-Output 'I18N_HARDCODE_CHECK_PASSED'
exit 0
