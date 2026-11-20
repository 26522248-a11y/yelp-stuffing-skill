# Architecture

Text sequence of one worker. Two workers run the same code with `BID` 0 and 1, which shifts the ports.

```text
pool.ps1
  |- slice source -> chunks/chunk_NNN.txt (15 lines)
  |- pick account -> check fresh session (curl /login/)
  |- spawn: BID=w LIST=chunk OUT=jsonl PU_BASE=... PW=... PACE=14 BUDGET=15 node batch-fast.js
       |
       |- disk guard (statfs < 2 GB -> abort)
       |- relay.listen(127.0.0.1:8986+BID)  -- CONNECT + Proxy-Authorization
       |- chrome --proxy-server=127.0.0.1:8986+BID --remote-debugging-port=9306+BID
       |- CDP /json/version -> WebSocket
       |- attach to the page target (flatten)
       |- poll /login/ until outerHTML > 200k + title "Log In"     [ddok]
       |- navigate /login/, wait #ajax-login + hcaptcha + > 400k  [hydrate] x4
       |- arm widget from [data-hcaptcha-widget-id]
       |- read csrftok
       |- loop i < min(15, rows):
       |    |- pace window check (PACE=14/min)
       |    |- hcaptcha.execute -> poll getResponse 150 ms, 24 s cap
       |    |- fetch /login/newajax (4 fields)
       |    |- 429 -> 13 s sleep, retry (3 attempts)
       |    |- 403/407 -> blocked, break chunk
       |    |- classify + record JSONL
       |    |- success -> sleep 2 s, GET /profile, Network.getAllCookies,
       |                  record zssLen, logout, re-hydrate
       |- summary record
       |- kill chrome, rm profile, close relay
```

## Ports and paths

| Item | Value |
|---|---|
| Relay | `127.0.0.1:8986+BID` |
| CDP | `127.0.0.1:9306+BID` |
| Profile | `%TEMP%\cdp-f<BID>-<epoch>` |
| Chrome | user-data-dir above, `--disable-blink-features=AutomationControlled` |

Ports tied to `BID` mean leftover processes block the next run; kill before start.

## Data flow

```text
source list -> chunk -> worker -> runs/<batch>/w<wave>-<w>.jsonl
                                 -> state.txt (offset by recorded rows)
                                 -> missed.txt (dedup union of unrecorded rows)
                                 -> report.ps1 -> classified.csv + hits.txt
```

Each credential record carries `i`, `email`, `pass`, `status`, verdict booleans, `tokLen`, `tokMs`, `postMs`, 110
bytes of `body`, and on success `profileStatus`, `zss` count, `zssLen`. The JSONL is the primary evidence; the CSV is
derived.

## Where each failure lands

| Stage | Failure | Detector | Handling |
|---|---|---|---|
| intake | 407 | gate | account marked QUOTA, skipped |
| launch | no CDP | `/json/version` 40 tries | `err:cdp`, abort |
| DataDome | no real DOM | `ddok` after 50 s | `abort:dd` |
| hydrate | shell only | 4 rounds x 20 s | `abort:hydrate` |
| widget | no api / render error | `armed` string | `abort:widget` |
| mint | 0-length token | 24 s cap | `tokFail`, POST with empty token -> `unable` |
| POST | 429 | status | 13 s sleep, retry row |
| POST | 403 | status | block chunk, new IP |
| POST | 407 | status | block chunk, drop account |
| success | logout race | re-hydrate fail | `rehydrate_fail`, block chunk |
| disk | ENOSPC | `statfsSync` | abort before launch |

## Why these shapes

- **Relay instead of Chrome proxy auth:** Chrome cannot take proxy credentials on the CLI; a local CONNECT relay
  injects `Proxy-Authorization` without a dialog. No external dependency.
- **In-page fetch instead of a form submit:** no React state, no button race, no navigation, body stays readable.
- **One page per browser:** `Target.getTargets` picks the first `page`; extra tabs break attachment.
- **Relaunch instead of rotate:** tearing down the relay under a live Chrome kills its network service.
- **15 rows per IP:** sits under both known ceilings (16/min, 30/IP) with margin.
