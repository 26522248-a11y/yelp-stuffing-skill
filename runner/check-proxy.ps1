param(
  [string[]]$Accounts = @(),          # "user:pass" list; defaults to $env:PU_BASE / $env:PW
  [string]$ProxyHost = "pr.oxylabs.io",
  [int]$ProxyPort = 7777
)

# Health gate. An account is usable only if a FRESH session returns 200 on /login/.
# Run this before every batch and after any chunk that produced 403/NO_POST.

$targets = if ($Accounts.Count -gt 0) { $Accounts } else { @($env:PU_BASE + ":" + $env:PW) }
$results = @()

foreach ($a in $targets) {
  $u = ($a -split ':', 2)[0]
  $p = ($a -split ':', 2)[1]
  $sess = "chk" + (Get-Random -Minimum 100000 -Maximum 999999)
  $cred = $u + "-sessid-" + $sess + "-sesstime-10:" + $p

  $code = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 40 -x "${ProxyHost}:${ProxyPort}" -U $cred "https://www.yelp.com/login/" 2>$null) -join ""
  $ipJson = (& curl.exe -s --max-time 30 -x "${ProxyHost}:${ProxyPort}" -U $cred "https://ip.oxylabs.io/location" 2>$null) -join ""
  $ip = "?"
  try { $ip = ($ipJson | ConvertFrom-Json).ip } catch {}

  $state = if ($code -eq "200") { "CLEAN" } elseif ($code -eq "403") { "DIRTY" } elseif ($code -eq "407") { "QUOTA" } else { "DEAD" }
  $results += [pscustomobject]@{ account = $u; ip = $ip; login = $code; state = $state }
  Write-Output ("{0,-42} {1,-11} login={2} {3}" -f $u, $ip, $code, $state)
}

$bad = @($results | Where-Object { $_.state -ne "CLEAN" })
Write-Output ""
Write-Output ("clean={0} dirty={1} quota={2} dead={3}" -f @($results | Where-Object { $_.state -eq "CLEAN" }).Count, @($results | Where-Object { $_.state -eq "DIRTY" }).Count, @($results | Where-Object { $_.state -eq "QUOTA" }).Count, @($results | Where-Object { $_.state -eq "DEAD" }).Count)
if ($bad.Count -gt 0) {
  Write-Output "DIRTY = DataDome on a fresh IP; QUOTA = 407 traffic limit on the Oxylabs account; DEAD = 000/timeout/auth."
  Write-Output "Rotate DIRTY, top up QUOTA, drop DEAD. A 403 on a fresh session means the IP pool is burned."
  exit 1
}
exit 0
