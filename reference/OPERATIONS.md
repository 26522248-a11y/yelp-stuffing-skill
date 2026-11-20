# Operations runbook

Everything here is one operator, one Windows box, PowerShell 5.1. Times are wall clock.

## 1. Session start (5 min)

```powershell
cd C:\Users\Administrator\yelp-skill-v2
Get-Process node,chrome -ErrorAction SilentlyContinue | Stop-Process -Force
Get-ChildItem $env:TEMP -Directory -Filter "cdp-*" | Remove-Item -Recurse -Force
(Get-PSDrive C).Free / 1GB            # must be >= 2
Get-Content .\runs\state.txt          # read only
(Get-Content .\runs\missed.txt).Count # read only
```

If disk < 2 GB, delete `cdp-*` and `%TEMP%\*chrome*`; if still < 2 GB, stop and report.

## 2. Proxy intake

Accounts arrive as `host:port:user:pass` or `user:pass`. Normalise to `user:pass` in `proxies.txt`, one per line.
Remove duplicates.

```powershell
.\runner\check-proxy.ps1 -Accounts (Get-Content .\proxies.txt)
```

| State | Meaning | Action |
|---|---|---|
| CLEAN | fresh session 200 | keep |
| DIRTY | 403 on a fresh IP | drop for this pass; re-test tomorrow |
| QUOTA | 407 | drop; needs top-up |
| DEAD | 000 / timeout / auth | drop |

Only CLEAN lines stay in the active pool. Expect 30-60 % to survive.

## 3. Acceptance

```powershell
.\runner\smoke.ps1 -PoolFile .\proxies.txt
```

Pass = `SMOKE PASS`, 6 rows, no 403/429/407, <= 1 unknown. Fail: do not start a long pass; consult `PITFALLS.md`.

## 4. Run

```powershell
.\runner\run-all.ps1 -Source "$env:TEMP\opencode\combo.bin" -PoolFile .\proxies.txt -Take 150 -Chunk 15 -Workers 2
```

- `-Take` is the batch (10 chunks), not a target.
- Batch sizing: `ceil(clean_accounts / 2) * 15` rows. 6 accounts -> 45-90 rows, not 300.
- Run in the foreground with a timeout you can watch, or background and poll every 3-5 min.
- Each wave logs one `wave N accounts=...` line. Read it; do not let 5 dead waves accumulate unnoticed.

## 5. Monitoring thresholds

| Observation | Action |
|---|---|
| 403 in a wave | normal at the tail; the chunk ends |
| 429 | normal if isolated; runner retries after 13 s |
| 2 consecutive waves with < 50 % rows | rotate more aggressively, shrink batch |
| 2 consecutive 0-row waves | stop, gate the pool again |
| 3 consecutive 0-row waves | run stops itself; report and request proxies |
| Disk < 2 GB | clean profiles mid-run, then continue |
| Chrome count > 2, node > 2 | kill orphans before the next wave |

## 6. Stop conditions

Stop immediately, even mid-batch, on:

1. Third consecutive 0-row wave (automatic).
2. Disk < 2 GB after cleanup.
3. `SMOKE FAIL` twice in a row.
4. Pool clean count < 2.
5. Operator says stop.

Never stop mid-chunk manually: the row is queued, not lost, but a half-written JSONL wastes the IP.

## 7. Close-out

```powershell
Get-Process node,chrome -ErrorAction SilentlyContinue | Stop-Process -Force
Get-ChildItem $env:TEMP -Directory -Filter "cdp-*" | Remove-Item -Recurse -Force
.\runner\report.ps1 -RunDir .\runs -HitsFile .\hits.txt -OutCsv .\classified.csv
```

Then: append hits to `reference/STATE.md` (or `VALID_ALL.txt`), update `progress.jsonl` reading, verify every new hit
per `SKILL.md` section 7, and report with the template in `docs/HANDOVER.md`.

## 8. Queue handling

`runs/missed.txt` is re-run as a source, never as an append target:

```powershell
.\runner\run-all.ps1 -Source .\runs\missed.txt -PoolFile .\proxies.txt -Root .\runs\retry
```

When the retry run is done, rows that got records leave the queue naturally on the next dedupe pass; do not hand-delete.

## 9. Reporting cadence

One line per batch is enough for the operator; a full table only when asked. Always report 403/429/407 and pool state,
because that is the signal the operator acts on.

## 10. What the operator supplies

Proxy accounts, and decisions about scope. Everything else is yours: gating, batching, queue, evidence, disk.
