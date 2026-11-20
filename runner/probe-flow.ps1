param(
  [Parameter(Mandatory=$true)][string]$Account,
  [Parameter(Mandatory=$true)][string]$Control,
  [string]$ProxyHost = "pr.oxylabs.io",
  [int]$ProxyPort = 7777,
  [string]$Out = ".\runs\probe",
  # Fixed sticky session: same value on another machine = same exit IP, so two runs are comparable.
  [string]$Sess = "",
  [int]$SessTime = 600
)

# One-IP probe of the submit path. Answers: does Yelp's own widget still mint a trusted token,
# and does the endpoint still compare passwords?
#
# -Account  "user:pass" sticky proxy account
# -Control  "email:password" known-good credential (use one of the verified hits)
# Exit: 0 = validated/success (submit path viable), 1 = link/unable (flow changed), 2 = crash.

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonl = Join-Path $Out ("probe_" + $stamp + ".jsonl")

$u = ($Account -split ':', 2)[0]; $p = ($Account -split ':', 2)[1]
$e = ($Control -split ':', 2)[0]; $pw = ($Control -split ':', 2)[1]

if (-not $Sess) { $Sess = "pb" + (Get-Random -Minimum 100000 -Maximum 999999) }
$cred = $u + "-sessid-" + $Sess + "-sesstime-" + $SessTime + ":" + $p
$code = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 35 -x "${ProxyHost}:${ProxyPort}" -U $cred "https://www.yelp.com/login/" 2>$null) -join ""
Write-Output ("gate login=${code} sess=$Sess")
if ($code -ne "200") { Write-Output "PROBE BLOCKED: account not clean"; exit 1 }

$env:OUT = $jsonl; $env:PU_BASE = $u; $env:PW = $p; $env:EMAIL = $e; $env:PASS = $pw; $env:SESS = $Sess; $env:SESSTIME = "$SessTime"
$env:PROXY_HOST = $ProxyHost; $env:PROXY_PORT = "$ProxyPort"
node (Join-Path $PSScriptRoot "probe-submit.js")
$rc = $LASTEXITCODE

$res = @(Get-Content $jsonl | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_.event -eq 'result' })
$w = @(Get-Content $jsonl | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_.event -eq 'widget_presence' })

if ($w.Count) { Write-Output ("widgets in DOM before: " + ($w[0].before | ConvertTo-Json -Compress)) }
if (-not $res.Count) { Write-Output "PROBE FAIL: no result"; exit 2 }
Write-Output ("verdict=" + $res[0].verdict + " status=" + $res[0].status)
Write-Output ("body=" + $res[0].body)

switch ($res[0].verdict) {
  "validated" { Write-Output "PROBE PASS: submit path compares passwords - port batch-fast to submit"; exit 0 }
  "success"   { Write-Output "PROBE PASS: submit path logged in - port batch-fast to submit"; exit 0 }
  "nav-success" { Write-Output "PROBE PASS: submit logged in (page navigated, XHR body lost)"; exit 0 }
  "link"      { Write-Output "PROBE FAIL: even the site token routes to magic-link - global flow change"; exit 1 }
  default     { Write-Output "PROBE FAIL: " + $res[0].verdict; exit 1 }
}
