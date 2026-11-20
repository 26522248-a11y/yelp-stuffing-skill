---
name: yelp-stuffing
description: Run or resume the Yelp credential-validation pipeline. DataDome path bypass, in-page invisible hCaptcha, 2-worker sticky-proxy pool, 15 rows per IP, evidence-first verdicts. Use when asked to continue the combo run, validate Yelp credentials, or rebuild the pipeline.
---

# Yelp credential validation - operating skill

Production-measured, 2026-11. Read `reference/STATE.md` before the first request and `docs/HANDOVER.md` if you are new.
Everything below is a hard rule unless marked "why" or "measured".

## 0. Facts that decide the design

| Fact | Value | Evidence |
|---|---|---|
| `/login` (no slash) | 403 always | 1000/1000 |
| `/login/` (slash) | 200 always | 1000/1000, datacenter and mobile |
| Verdict endpoint | `POST /login/newajax` | JSON body, no navigation |
| Captcha field | `hcaptcha_response` | wrong name = fail-closed |
| Captcha difficulty | invisible, self-solving | 0 solvers, 0 cost |
| 429 threshold | ~16 POST / rolling minute / IP | burst run, rows 16-19 |
| 403 threshold | ~32 POST / sticky IP | first 403 at row 32 |
| Re-hydrate refreshes IP reputation | no | 403 wall unchanged |
| Token bound to IP | no, but cross-IP loses the verdict | 200 + magic link |
| Stable workers on 4 GB RAM | 2 | 3 workers: 0 verdicts |
| Temp disk floor | 2 GB | ENOSPC looked like DataDome for hours |

## 1. Hard rules

1. Target `https://www.yelp.com/login/` - never `/login`.
2. Post to `/login/newajax` with exactly `csrftok`, `email`, `password`, `hcaptcha_response`.
3. One hydration per IP; 15 POST per IP; then kill Chrome and take a new session.
4. Never reuse a session, a token, or a Chrome profile.
5. Health-gate every fresh session with `200` on `/login/`. 403 = dirty, 407 = quota, 000 = dead.
6. Two workers maximum. Three starve on 4 GB.
7. Abort below 2 GB free temp disk; delete `%TEMP%\cdp-*` on exit.
8. Capture bodies through `Network.loadingFinished`, never the DOM alert, never `Fetch` interception.
9. Mint the token immediately before the POST, same IP, and treat it as single-use.
10. Only `success:true` + `zss` >= 20 + `/profile` 200 is a hit.
11. Unresolved rows (link, unable, 403, 407, 429, -1, empty) go to the queue. Never count them as wrong.
12. Resume from `state.txt`; never lower it by hand.

## 2. How to think about the target

Yelp's login is gated by three independent layers, and they fail differently:

| Layer | What it does | How it shows | What beats it |
|---|---|---|---|
| Path router | `/login` goes to a 403 shard | HTML 403, "Access Denied" | always use `/login/` |
| DataDome | scores IP + session | empty page, `ddok=false`, 403 on POST | fresh sticky mobile IP, <=15 POST, 1 Chrome per IP |
| hCaptcha | risk-triggered challenge | `"unable to log you in"` | site widget inside a real browser, token in `hcaptcha_response` |

There is no application-level lockout: the same account can be tried repeatedly across IPs, and 7 wrong passwords do
not lock it. The only app-level brakes are 429 (per minute) and 403 (per IP lifetime).

Consequence: **throughput is a proxy problem, not a script problem.** The script is done. What limits a run is how many
clean sticky IPs you can supply. Plan pool burn: one account is good for ~15-45 rows, a 30-account pool for ~300-450.

## 3. Prerequisites

| Item | Requirement |
|---|---|
| OS | Windows 10/11, PowerShell 5.1 |
| Node | >= 22 (`fetch`, `WebSocket`, `statfsSync`) |
| Chrome | `C:\Program Files\Google\Chrome\Application\chrome.exe` or `$env:CHROME` |
| Proxies | Oxylabs sticky accounts, `customer-mobile_<uuid>-cc-us:<password>`, one per line |
| RAM | 4 GB; 2 workers |
| Disk | >= 2 GB free |
| Input | `email:password` ASCII, one per line; `# . ~ + = _ ! ?` are legal in passwords |

Sticky IPs come from the username suffix `-sessid-<random>-sesstime-1800`; the runner appends it. A raw
`customer-...` username is a rotating IP and will change mid-chunk.

`407 Access denied: traffic limit reached` is the Oxylabs account quota. It is not a Yelp block and retrying the account
is useless.

## 4. Files in the pipeline

| File | Role |
|---|---|
| `runner/batch-fast.js` | one worker: relay, Chrome, CDP, hydrate, mint, POST, classify, evidence |
| `runner/pool.ps1` | orchestrator: slices the list into 15-row chunks, health-gates an account per chunk, 2 workers |
| `runner/run-all.ps1` | full-list loop: resume, missed queue, 3-dead-wave stop |
| `runner/check-proxy.ps1` | session gate: CLEAN / DIRTY / QUOTA / DEAD |
| `runner/smoke.ps1` | 6-row acceptance test after any site change |
| `runner/report.ps1` | aggregate verdicts, CSV, hits file |

## 5. Run loop

```powershell
# once per session
cd C:\Users\Administrator\yelp-skill-v2
$env:NODE_OPTIONS = ""
Get-Process node,chrome -ErrorAction SilentlyContinue | Stop-Process -Force
Get-ChildItem $env:TEMP -Directory -Filter "cdp-*" | Remove-Item -Recurse -Force

# intake: only CLEAN accounts survive
.\runner\check-proxy.ps1 -Accounts (Get-Content .\proxies.txt)

# acceptance: 6 rows, must pass before a long pass
.\runner\smoke.ps1 -PoolFile .\proxies.txt

# run / resume
.\runner\run-all.ps1 -Source "$env:TEMP\opencode\combo.bin" -PoolFile .\proxies.txt -Take 150 -Chunk 15 -Workers 2
```

Inside one worker the order is fixed:

1. relay listens on `127.0.0.1:8986+BID`, Chrome on `9306+BID`, profile under `%TEMP%\cdp-f<BID>-<ts>`.
2. Chrome opens `/login/`; poll until `outerHTML > 200k` and title `Log In` -> `ddok:true`.
3. `hydrate()`: navigate, wait for `#ajax-login`, `window.hcaptcha`, `outerHTML > 400k`.
4. `armWidget()`: take the page's `[data-hcaptcha-widget-id]`; self-render only if absent.
5. read `csrftok` from `#ajax-login`.
6. per credential: `hcaptcha.execute` -> poll `getResponse` 150 ms -> POST -> classify -> record.
7. on success: sleep 2 s, `GET /profile`, read cookies, then logout + re-hydrate.
8. at 15 POST: summary, kill Chrome, delete profile, exit.

## 6. Classification

Priority order, first match wins:

| Verdict | Test | Meaning |
|---|---|---|
| `success` | `success === true` | password accepted; verify session |
| `nosession` | `success === true` without `zss`/`/profile` | accepted, session not established |
| `validated` | `error_fields` contains `password` and body has `incorrect` | server compared and rejected |
| `closed` | `has been closed` | email exists, account closed |
| `link` | `require_link` / `magic_link` / `login link` | routed to email confirmation |
| `unable` | `unable to log you in` | captcha/risk fail-closed |
| `429` / `407` / `403` | status | throttle / quota / block |
| `NO_POST` | no record | page never submitted |
| `other` | anything else | inspect manually |

Only `success`, `validated`, `closed` are verdicts. `validated`, `closed` still leak intelligence: the email exists.

## 7. Hit verification (mandatory)

1. In the same record: `success:true`, `zssLen >= 20`, `profileStatus:200`.
2. Replay the pair on a fresh session; `success:true` and a new `zss` again.
3. `GET /profile` with the cookie jar returns 200 and the account name.
4. Report email, password, and the three artifacts. A pair backed only by `"incorrect"` is not a hit.

## 8. Failure playbook

| Symptom | Cause | Fix |
|---|---|---|
| `ddok=false` after 50 s | IP burned | new session; do not debug the page |
| 403 on first POST | IP spent | rotate; 403 starts at POST 32 |
| 429 | >15 POST/min | runner sleeps 13 s and retries the same row; if it repeats, rotate |
| 407 | quota | drop account, top up |
| page < 400 kB | not hydrated | wait for `#ajax-login` + 400 kB, 4 rounds |
| `fire()` 0 | password field hidden | click `.login-with-password-link` (form path only) |
| empty bodies only on hits | captured with `Fetch` | `Network.loadingFinished` -> `getResponseBody` |
| all slow, no 403/429 | disk full | delete `cdp-*`, keep 2 GB |
| 0 verdicts on 3 workers | RAM | 2 workers |
| hit then `rehydrate_fail` | logout race | chunk ends; next chunk new IP |
| repeated magic-link | token minted on another IP | mint and POST on the same session |
| every POST `"unable"` with a valid token | wrong field name or self-rendered widget | `hcaptcha_response`; site widget |

## 9. Throughput

| Stage | Measured |
|---|---|
| token mint | 0.8-2.1 s |
| POST + body | 0.8-1.3 s |
| hydration | 5-12 s per IP |
| launch + DataDome | 15-25 s per IP |
| 15-row chunk | 55-90 s |
| aggregate | 11-30 rows/min, 660-1,800/hour |

Do not add browsers. Add proxies.

## 10. Resume and queue

- `runs/state.txt` = next offset. It advances by **rows actually recorded**.
- `runs/missed.txt` = rows from a window that died out of order, deduplicated. Run it as a normal source:

```powershell
.\runner\run-all.ps1 -Source .\runs\missed.txt -PoolFile .\proxies.txt -Root .\runs\retry
```

- `runs/progress.jsonl` = one record per batch: rows, validated, success, closed, 403, 429, rate.
- Three consecutive 0-row waves stop the run; state is untouched, so the same command resumes later.

## 11. Do / Don't

Do: keep 2 workers, 15 rows, 2 GB free, ASCII lists, one hydration per IP, evidence JSONL, fresh session per chunk.

Don't: use `/login`, rename the captcha field, reuse a token, rotate the IP inside a live Chrome, use a solver, read the
DOM alert, report `"incorrect"` as a hit, lower `state.txt`, run 300-row batches on a small pool.

## 12. Map

`docs/HANDOVER.md` (start) - `reference/CONTEXT.md` - `TARGET.md` - `RESPONSE-MATRIX.md` - `OPERATIONS.md` -
`CHECKLISTS.md` - `PITFALLS.md` - `MEASUREMENTS.md` - `STATE.md` - `GLOSSARY.md`.
