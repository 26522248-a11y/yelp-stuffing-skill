param(
  [Parameter(Mandatory=$true)][string]$PoolFile,
  [string]$Source = "",
  [Parameter(Mandatory=$true)][string]$Control,
  [int]$Rows = 6,
  [int]$MaxUnknown = 1,
  [int]$MaxLink = 0,
  [switch]$AllowOwnWidget
)

# Acceptance gate. Proves FOUR things, not just "no 403":
#   1. the page hydrates and the SITE widget is in the DOM (own widget = token without rqdata)
#   2. Yelp still COMPARES passwords (>= 4 validated) - a real control must also log in
#   3. the auth flow is still password, not email-confirmation (link == 0)
#   4. no 403/429/407 and all rows return
#
# -Control = a verified pair from reference/STATE.md. Without a control, success is not proven.
# Run after ANY site change, before every pass. Own run root, real state untouched.

$ErrorActionPreference = "Stop"
$root = Join-Path (Join-Path $PSScriptRoot "..") "runs\smoke"
if (-not $Source) { $Source = Join-Path (Join-Path $PSScriptRoot "..") "examples\combo.sample.txt" }
if (-not (Test-Path $Source)) { throw "source not found: $Source" }

$poolScript = Join-Path $PSScriptRoot "pool.ps1"
$outDir = Join-Path $root (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Put the control first, then Rows-1 list rows. The control is the assertion; it must always be exercised.
$ctrlEmail = ($Control -split ':', 2)[0]
$body = @()
if (Test-Path $Source) { $body = @(Get-Content $Source | Where-Object { $_ -match ':' -and $_.Trim() -ne '' }) }
$scan = @($body | Where-Object { ($_ -split ':', 2)[0] -ne $ctrlEmail })
$inputFile = Join-Path $outDir "smoke_input.txt"
@($Control.Trim()) + @($scan | Select-Object -First ([Math]::Max(0, $Rows - 1))) | Set-Content -Encoding ascii $inputFile

$log = & $poolScript -Source $inputFile -PoolFile $PoolFile -Skip 0 -Take $Rows -Chunk $Rows -Workers 1 -Pace 14 -OutDir $outDir 2>&1
$log | Select-Object -Last 3

$ev = @()
foreach ($f in (Get-ChildItem $outDir -Filter *.jsonl -ErrorAction SilentlyContinue)) {
  $ev += @(Get-Content $f.FullName | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
}
$j = @($ev | Where-Object { $_.email })
$armed = ($ev | Where-Object { $_.event -eq 'widget' } | Select-Object -First 1).armed
$rowsDone = $j.Count
$val = @($j | Where-Object { $_.validated }).Count
$suc = @($j | Where-Object { $_.success }).Count
$link = @($j | Where-Object { $_.link }).Count
$unknown = @($j | Where-Object { -not $_.validated -and -not $_.success -and -not $_.link -and -not $_.closed -and -not $_.unable -and -not $_.status }).Count
$r403 = @($j | Where-Object { $_.status -eq 403 }).Count
$r429 = @($j | Where-Object { $_.status -eq 429 }).Count
$r407 = @($j | Where-Object { $_.status -eq 407 }).Count
$ctl = @($j | Where-Object { $_.email -eq ($Control -split ':', 2)[0] } | Select-Object -First 1)

$fail = @()
if ($rowsDone -lt $Rows) { $fail += "rows=$rowsDone/$Rows" }
if ($r403 -gt 0) { $fail += "403=$r403" }
if ($r429 -gt 0) { $fail += "429=$r429" }
if ($r407 -gt 0) { $fail += "407=$r407 (quota)" }
if ($unknown -gt $MaxUnknown) { $fail += "unknown=$unknown" }
if ($link -gt $MaxLink) { $fail += "link=$link/$rowsDone (email-confirm flow)" }
if ($val -lt [math]::Ceiling($Rows * 0.6)) { $fail += "validated=$val/$Rows (password not compared)" }
if (-not $ctl) { $fail += "control missing from output" }
elseif (-not $ctl.success -or -not ($ctl.zssLen -ge 20)) { $fail += "control did not log in (profile=$($ctl.profileStatus) zss=$($ctl.zssLen))" }
if (-not $armed) { $fail += "no widget event" }
elseif ($armed -notlike "site:*" -and -not $AllowOwnWidget) { $fail += "armed=$armed (own widget, no rqdata)" }

Write-Output ("armed=$armed validated=$val success=$suc link=$link unknown=$unknown 403=$r403 429=$r429 407=$r407")
if ($fail.Count -gt 0) { Write-Output ("SMOKE FAIL: " + ($fail -join ", ")); exit 1 }
Write-Output ("SMOKE PASS rows={0} validated={1} control=success widget=site" -f $rowsDone, $val)
exit 0
