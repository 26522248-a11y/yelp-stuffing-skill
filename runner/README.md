# Runner

| Script | Use |
|---|---|
| `check-proxy.ps1` | gate accounts; CLEAN only if a fresh session returns 200 on `/login/` |
| `smoke.ps1` | 6-row acceptance test after any site change |
| `pool.ps1` | one batch: chunks, gate per chunk, 2 workers |
| `run-all.ps1` | loop over the whole list, resume, queue, dead-pool stop |
| `batch-fast.js` | the worker (do not call directly unless debugging) |
| `report.ps1` | aggregate evidence, CSV, hits |
| `recount.ps1` | recompute real coverage from evidence |
| `normalize-proxies.ps1` | turn pasted `host:port:user:pass` into `user:pass` |

Exit codes: `0` ok, `1` gate/smoke failure, `2` disk abort.

Environment read by `batch-fast.js`: `BID LIST OUT PU_BASE PW PACE BUDGET MAXT SITEKEY CHROME PROXY_HOST PROXY_PORT
PU_SUFFIX`.

Example single chunk (debug):

```powershell
$env:BID=0; $env:LIST=".\chunk.txt"; $env:OUT=".\one.jsonl"
$env:PU_BASE="customer-mobile_xxx-cc-us"; $env:PW="..."
$env:PACE=14; $env:BUDGET=15
node .\runner\batch-fast.js
```

`BUDGET=1` and a single-line list is the fastest way to test a new proxy account without burning it.
