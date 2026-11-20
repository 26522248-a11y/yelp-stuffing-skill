param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$PoolFile,
  [Alias('Skip')][int]$StartAt = 0,
  [int]$Take = 150,
  [int]$Chunk = 15,
  [int]$Workers = 2,
  [int]$Pace = 14,
  [int]$MaxDeadWaves = 3,
  [string]$Root = ".\runs"
)

# Runs the remaining list in resumable batches.
# - state.txt      : next offset (advances by rows actually recorded, not by Take)
# - progress.jsonl : one record per batch
# - missed.txt     : rows in a window that produced no record (out-of-order chunk death)
#                    Deduplicated on write; re-run with -Source runs/missed.txt -Root runs/retry
#
# Stops after MaxDeadWaves consecutive waves that record 0 rows (pool dead) instead of
# grinding through the rest of the list at full cost.

$ErrorActionPreference = "Continue"

# Preflight: the runner needs Node >= 22 (global fetch + WebSocket) and Chrome.
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) { throw "node not found on PATH (need Node >= 22)" }
$nodeMajor = [int]((& node -v).TrimStart('v').Split('.')[0])
if ($nodeMajor -lt 22) { throw "Node $nodeMajor is too old; need >= 22 for global fetch/WebSocket" }
$chrome = if ($env:CHROME) { $env:CHROME } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
if (-not (Test-Path $chrome)) { throw "Chrome not found at $chrome (set `$env:CHROME)" }
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
if (-not (Test-Path $PoolFile)) { throw "pool not found: $PoolFile" }

$poolScript = Join-Path $PSScriptRoot "pool.ps1"
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$progress = Join-Path $Root "progress.jsonl"
$stateFile = Join-Path $Root "state.txt"
$missedFile = Join-Path $Root "missed.txt"

$allLines = Get-Content $Source | Where-Object { $_ -match ':' -and $_.Trim() -ne '' }
$total = $allLines.Count
$offset = $StartAt
if (Test-Path $stateFile) {
  $saved = [int](Get-Content $stateFile -TotalCount 1)
  if ($saved -gt $offset) { $offset = $saved }
}

Write-Output ("start offset={0} total={1} take={2} chunk={3} workers={4}" -f $offset, $total, $Take, $Chunk, $Workers)
$deadWaves = 0

while ($offset -lt $total) {
  $free = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
  if ($free -lt 2) {
    Get-ChildItem $env:TEMP -Directory -Filter "cdp-*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $free = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    if ($free -lt 2) { Write-Output ("STOP disk free={0}GB" -f $free); break }
  }

  $outDir = Join-Path $Root ("batch_{0:d5}" -f $offset)
  $window = @($allLines | Select-Object -Skip $offset -First $Take)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $log = & $poolScript -Source $Source -PoolFile $PoolFile -Skip $offset -Take $Take -Chunk $Chunk -Workers $Workers -Pace $Pace -OutDir $outDir 2>&1
  $sw.Stop()
  Write-Output (($log | Select-Object -Last 2) -join " | ")

  $rows = 0; $val = 0; $suc = 0; $closed = 0; $r403 = 0; $r429 = 0
  foreach ($line in ($log | Where-Object { $_ -like "TOTAL*" })) {
    if ($line -match 'rows=(\d+)') { $rows = [int]$matches[1] }
    if ($line -match 'validated=(\d+)') { $val = [int]$matches[1] }
    if ($line -match 'success=(\d+)') { $suc = [int]$matches[1] }
    if ($line -match 'closed=(\d+)') { $closed = [int]$matches[1] }
    if ($line -match '403=(\d+)') { $r403 = [int]$matches[1] }
    if ($line -match '429=(\d+)') { $r429 = [int]$matches[1] }
  }
  $el = [math]::Round($sw.Elapsed.TotalSeconds)
  [pscustomobject]@{
    offset = $offset; rows = $rows; validated = $val; success = $suc; closed = $closed
    r403 = $r403; r429 = $r429; secs = $el
    rowsPerMin = if ($el -gt 0) { [math]::Round(60.0 * $rows / $el, 1) } else { 0 }
    time = (Get-Date).ToString("s")
  } | ConvertTo-Json -Compress | Add-Content -Path $progress -Encoding UTF8

  # Advance by rows actually recorded so a dead chunk does not skip the rows behind it.
  # Rows without a record in this window are queued; the next offset may overlap them,
  # which is harmless and cheaper than losing them.
  if ($rows -lt $window.Count) {
    $seen = @{}
    foreach ($jf in (Get-ChildItem $outDir -Filter *.jsonl -ErrorAction SilentlyContinue)) {
      Get-Content $jf.FullName -ErrorAction SilentlyContinue | ForEach-Object {
        try { $o = $_ | ConvertFrom-Json } catch { return }
        if ($o.email) { $seen[$o.email] = $true }
      }
    }
    $missed = @($window | Where-Object { -not $seen[$_.Split(':')[0]] })
    if ($missed.Count -gt 0) {
      $existing = if (Test-Path $missedFile) { @(Get-Content $missedFile -ErrorAction SilentlyContinue) } else { @() }
      @($existing + $missed) | Where-Object { $_ } | Sort-Object -Unique | Set-Content -Path $missedFile -Encoding ascii
      Write-Output ("missed {0} rows -> queue" -f $missed.Count)
    }
  }

  $advance = if ($rows -gt 0) { [Math]::Min($rows, $window.Count) } else { 0 }
  if ($advance -eq 0) {
    $deadWaves++
    Write-Output ("dead wave {0}/{1}" -f $deadWaves, $MaxDeadWaves)
    if ($deadWaves -ge $MaxDeadWaves) {
      Write-Output "STOP pool is dead; rerun the same command later (state is unchanged)"
      break
    }
  } else { $deadWaves = 0 }
  $offset += $advance
  Set-Content -Path $stateFile -Value $offset -Encoding ascii

  Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Get-ChildItem $env:TEMP -Directory -Filter "cdp-*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

Write-Output ("DONE offset={0} total={1}" -f $offset, $total)
