# Runner

> **2026-11-21:** the fast path is canonical. `batch-fast.js` no longer aborts on a self-rendered widget, and it
> ends the chunk on a hit. The canonical commands and the retry-queue wrapper are in
> https://github.com/26522248-a11y/yelp-auth-runbook (`runner/run-pool.ps1`).

| Script | Use |
|---|---|
| `check-proxy.ps1` | gate accounts; CLEAN only if a fresh session returns 200 on `/login/` |
| `smoke.ps1` | acceptance: verdicts + control; passes with `own` or `site` widget |
| `probe-flow.ps1` | one-IP probe of the submit path (fallback only) |
| `probe-submit.js` | probe worker: real form submit, CDP capture |
| `pool.ps1` | one batch: chunks, gate per chunk, 4 workers |
| `run-all.ps1` | loop over the whole list, resume, queue, dead-pool stop |
| `batch-fast.js` | the worker (fast path; call directly only for debugging) |
| `report.ps1` | aggregate evidence, CSV, hits |
| `recount.ps1` | recompute real coverage from evidence |
| `normalize-proxies.ps1` | turn pasted `host:port:user:pass` into `user:pass` |

Exit codes: `0` ok, `1` gate/smoke/probe failure, `2` disk abort or probe crash.

Environment read by `batch-fast.js`: `BID LIST OUT PU_BASE PW SESS PACE BUDGET MAXT SITEKEY CHROME PROXY_HOST
PROXY_PORT PU_SUFFIX`. Defaults: `PACE=12`, `BUDGET=28`, `PU_SUFFIX=-sesstime-1800`; set `PU_SUFFIX=none` for a
static proxy.

Example single chunk (debug):

```powershell
$env:BID=0; $env:LIST=".\chunk.txt"; $env:OUT=".\one.jsonl"
$env:PU_BASE="customer-mobile_xxx-cc-us"; $env:PW="..."
$env:PACE=12; $env:BUDGET=1
node .\runner\batch-fast.js
```

`BUDGET=1` and a single-line list is the fastest way to test a new proxy account without burning it.
