param(
  [Parameter(Mandatory=$true)][string]$PoolFile,
  [string]$Source = "",
  [int]$Rows = 6,
  [int]$MaxUnknown = 1
)

# Post-change smoke test: prove the page still hydrates, the widget still mints, and
# /login/newajax still returns classified bodies. Run after any Yelp UI change and
# before a long pass. Uses its own run root, so state.txt of the real run is untouched.
#
# Default source is examples/combo.sample.txt (fake addresses): a pass proves the
# pipeline, not a hit. Point -Source at a real short list to also prove verdicts.

$ErrorActionPreference = "Stop"
$root = Join-Path (Join-Path $PSScriptRoot "..") "runs\smoke"
if (-not $Source) { $Source = Join-Path (Join-Path $PSScriptRoot "..") "examples\combo.sample.txt" }
if (-not (Test-Path $Source)) { throw "source not found: $Source" }

$poolScript = Join-Path $PSScriptRoot "pool.ps1"
$outDir = Join-Path $root (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$log = & $poolScript -Source $Source -PoolFile $PoolFile -Skip 0 -Take $Rows -Chunk $Rows -Workers 1 -Pace 14 -OutDir $outDir 2>&1
$log | Select-Object -Last 3

$line = $log | Where-Object { $_ -like "TOTAL*" } | Select-Object -Last 1
$rowsDone = 0; $r403 = 0; $r429 = 0; $r407 = 0; $unknown = 0
if ($line -match 'rows=(\d+)') { $rowsDone = [int]$matches[1] }
if ($line -match '403=(\d+)') { $r403 = [int]$matches[1] }
if ($line -match '429=(\d+)') { $r429 = [int]$matches[1] }
if ($line -match '407=(\d+)') { $r407 = [int]$matches[1] }
if ($line -match 'unknown=(\d+)') { $unknown = [int]$matches[1] }

$fail = @()
if ($rowsDone -lt $Rows) { $fail += "rows=$rowsDone/$Rows" }
if ($r403 -gt 0) { $fail += "403=$r403" }
if ($r429 -gt 0) { $fail += "429=$r429" }
if ($r407 -gt 0) { $fail += "407=$r407 (quota)" }
if ($unknown -gt $MaxUnknown) { $fail += "unknown=$unknown > $MaxUnknown" }

if ($fail.Count -gt 0) { Write-Output ("SMOKE FAIL: " + ($fail -join ", ")); exit 1 }
Write-Output ("SMOKE PASS rows={0} 403=0 429=0 407=0 unknown={1}" -f $rowsDone, $unknown)
exit 0
