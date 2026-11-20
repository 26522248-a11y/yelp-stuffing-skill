param(
  [Parameter(Mandatory=$true)][string]$InFile,
  [Parameter(Mandatory=$true)][string]$OutFile
)

# Normalise pasted proxy lines into the only shape the runners accept: user:pass, one per line.
#
# Accepts:
#   host:port:user:pass      (what the operator usually pastes)
#   user:pass
# Drops comments, duplicates, QUOTA-looking empties. Writes ASCII. Never prints passwords.

$ErrorActionPreference = "Stop"
$seen = @{}
$out = New-Object System.Collections.Generic.List[string]
$dropped = 0

foreach ($raw in (Get-Content $InFile)) {
  $line = $raw.Trim()
  if (-not $line -or $line.StartsWith("#")) { continue }
  $user = $null; $pass = $null

  if ($line -match '^(?:[^:]+):(\d+):([^:]+):(.+)$') {
    $user = $matches[2]; $pass = $matches[3]
  } elseif ($line -match '^([^:]+):(.+)$') {
    $user = $matches[1]; $pass = $matches[2]
  } else { $dropped++; continue }

  if ($user -notmatch '^customer-') { $dropped++; continue }
  if (-not $pass) { $dropped++; continue }
  if ($seen.ContainsKey($user)) { continue }
  $seen[$user] = $true
  $out.Add($user + ":" + $pass)
}

$out | Set-Content -Path $OutFile -Encoding ascii
Write-Output ("accounts={0} dropped={1} -> {2}" -f $out.Count, $dropped, $OutFile)
Write-Output "next: .\runner\check-proxy.ps1 -Accounts (Get-Content $OutFile)"
