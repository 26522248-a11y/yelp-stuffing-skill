# Pitfall catalogue

Symptom -> cause -> fix. Every entry cost at least one run. Read before debugging anything.

## 1. Wrong captcha field name

Symptom: every POST returns `"We're unable to log you in right now."` with a fresh 1,900-char token.
Cause: the endpoint reads `hcaptcha_response` (underscore). `h-captcha-response` and `g-recaptcha-response` are
ignored, so the request is tokenless and fail-closes.
Fix: send exactly `csrftok`, `email`, `password`, `hcaptcha_response`.

## 2. Global password selector

Symptom: 60-75 s per credential, no POST, or a magic-link body.
Cause: three elements share `id=password` across different forms.
Fix: scope to `#ajax-login`; click `.login-with-password-link` if the field is hidden.

## 3. Reading via Fetch interception

Symptom: empty bodies almost only on successes.
Cause: success navigates away and `Fetch.getResponseBody` loses the resource.
Fix: `Network.loadingFinished` -> `Network.getResponseBody`.

## 4. Reading the DOM alert

Symptom: a plausible "5/5 success" streak that does not reproduce.
Cause: the AJAX flow does not change `uniqueRequestId`; the alert keeps the previous text.
Fix: bind every body to its request id.

## 5. Hydration judged by HTTP 200

Symptom: submit does nothing, page length 200-260 kB.
Cause: 200 is the pre-hydration shell.
Fix: require `#ajax-login` and `outerHTML > 400000`.

## 6. One session for the whole list

Symptom: 403s climbing, then mass `NO_POST`.
Cause: ~30 POST per IP, then DataDome blocks.
Fix: 15 rows per IP, new session, new Chrome.

## 7. Treating "unable to log you in" as a wrong password

Symptom: a chunk "validates" while nothing was compared.
Cause: captcha fail-closed returns the same body for every input.
Fix: separate counter, retry on a fresh IP.

## 8. Counting an unresolved row as negative

Symptom: hit rate drifts down, real hits disappear.
Fix: `NO_POST`/403/429 go to the re-check queue.

## 9. Restarting a capped run from zero

Symptom: duplicated work, burned IPs, inconsistent counts.
Fix: resume from `state.txt`.

## 10. Shell metacharacters in passwords

Symptom: `#`, `.`, `~`, `+`, `!` truncated, or proxy auth fails on `+`.
Fix: keep credentials in ASCII files, pass into JS via `JSON.stringify`.

## 11. Three Chrome instances

Symptom: 26 rows / 482 s, 0 verdicts, 20-80 s per row.
Cause: 4 GB RAM; one Chrome starves.
Fix: two workers maximum.

## 12. Trusting the proxy account instead of the session

Symptom: an account that tested 200 burns out after one chunk; a fresh session is 403.
Cause: the account is a pool; the session decides the IP.
Fix: health-gate per session.

## 13. Capsolver

Symptom: `We don't support this service` for `HCaptchaTask*`.
Fix: no solver. The invisible widget solves itself in headful Chrome with
`--disable-blink-features=AutomationControlled`.

## 14. Reporting headers from the 403 page

Symptom: "missing HSTS/CSP" that a triager disproves in one request.
Fix: inspect `/login/` (envoy), not the DataDome 403.

## 15. Treating "incorrect" as definitive

Symptom: the same pair returns `require_link` on another session.
Cause: Yelp routes some accepted credentials into email confirmation.
Fix: bucket link responses as `needs-email`. Only `success` + `zss` + `/profile` 200 is valid.

## 16. Quoting design targets as measurements

Symptom: a report claims a rate the next run cannot reproduce.
Fix: every number must come from a recorded run in `MEASUREMENTS.md`.

## 17. Assuming `/login/newajax` has no rate limit

Symptom: 429 at row ~16 after an earlier run did 41 POST cleanly.
Cause: the limit is per rolling minute; spaced requests hide it.
Fix: 15 POST per IP.

## 18. Full temp disk

Symptom: 20-80 s per row, blank/stalled page, no 403/429, zero verdicts; Node may throw `ENOSPC`.
Cause: each run leaves a 50-100 MB Chrome profile; 168 of them filled the volume.
Fix: delete `cdp-*` on exit, abort below 2 GB free.

## 19. Cross-IP token reuse

Symptom: token accepted but body is `"We had some trouble sending a login link"`.
Cause: minted on one IP, submitted from another.
Fix: mint and submit on the same IP; rotate between chunks.

## 20. In-browser IP rotation

Symptom: after rotating, four consecutive fresh IPs fail to hydrate.
Cause: destroying relay tunnels leaves Chrome's network service unable to reconnect.
Fix: rotate by relaunching Chrome (15-row chunks).

## 21. Reading 407 as a Yelp block

Symptom: every request returns 407 `Access denied: traffic limit reached`.
Cause: Oxylabs quota.
Fix: gate labels it `QUOTA`; drop the account.

## 22. Reusing a burned account because it once returned 200

Symptom: one worker is fine, the other produces 0 rows every wave.
Cause: rotation by index, no per-session check.
Fix: gate a fresh session before every chunk.

## 23. Advancing the offset by the batch size

Symptom: `state.txt` jumps 150 while only 15 rows have records.
Cause: `run-all` incremented by `-Take`.
Fix: advance by rows actually recorded, queue the shortfall.

## 24. Dropping the password from evidence

Symptom: report lists `email:` with an empty password.
Cause: the per-credential record omitted `pass`.
Fix: write `pass` on every record; dedupe hits on the pair.

## 25. Self-rendered hCaptcha widget

Symptom: token mints in 600-750 ms, correct field, every POST `"unable"`.
Cause: no site `rqdata`; token issued but rejected server-side.
Fix: reuse `[data-hcaptcha-widget-id]`; render only if absent.

## 26. Storing cookie count instead of cookie length

Symptom: `report.ps1` demotes real hits to `nosession` when `/profile` blips.
Cause: record stored `zss.length` (count) while the check expects a length.
Fix: store `zssLen` (max value length) and gate on >= 20 plus `/profile` 200.

## 27. Lowering `state.txt` by hand

Symptom: hundreds of rows run twice, queue and progress disagree.
Cause: "fixing" the offset after the old jump bug.
Fix: leave it. The gap rows are in `missed.txt`; the queue covers them.

## 28. Truncating `missed.txt`

Symptom: coverage can no longer be reconciled; the final report undercounts.
Fix: only `run-all` rewrites it, always as a union. Keep the previous copy if you edit manually.

## 29. Orphan Chrome / port collision

Symptom: CDP attaches to the previous run's page, or `/json/version` never answers.
Cause: relay ports are `8986+BID` and CDP ports `9306+BID`; leftovers hold them.
Fix: kill `node` and `chrome` before every batch.

## 30. Retrying inside a 403 chunk

Symptom: 3-4 minutes spent per dead chunk.
Cause: re-hydrate on 403.
Fix: 403 ends the chunk; only 429 retries the row.

## 31. Batch far larger than the pool

Symptom: 6 accounts, 300-row batch, 14 dead waves, ~5 min each.
Fix: `Take = ceil(clean/2) * 15`, usually 90-150.

## 32. Trusting an old gate result

Symptom: accounts that passed an hour ago now abort on `ddok`.
Cause: IPs decay with every POST from anyone on that pool.
Fix: gate immediately before the batch, not at intake only.

## 33. Reporting `closed` as valid

Symptom: hit count inflated by accounts nobody can log into.
Fix: `closed` is intelligence, not a hit.

## 34. Extra tabs in the worker browser

Symptom: `Target.attachToTarget` picks a blank page and every evaluate returns null.
Cause: `targetInfos.find(type === 'page')` takes the first page.
Fix: one tab per worker; close or ignore extras.

## 35. Using `-Take` as "rows to finish"

Symptom: a 150-row `Take` on a 20-row remainder throws `empty slice`.
Fix: `-Take` is a batch cap, not a target; the loop stops at end of list.


## 36. Reading the `TOTAL` 407 counter as real

Symptom: batches clearly hit quota, `report.ps1` and `TOTAL` show `407=0`.
Cause: `pool.ps1` counts 407 from credential records, but a 407 aborts the chunk before a record is written; only an
`event:r407` line exists.
Fix: count `event:r407` in the JSONL, not `status -eq 407` in the aggregate.

## 37. Conflating the offset with rows tested

Symptom: "2,707 rows tested" because the last tested row index was 2,707.
Cause: `state.txt` reserves a window; it advances past dead waves.
Fix: count unique credential records (`recount.ps1`). Report tested and offset as two separate numbers.

## 38. Classifying `status -1` as `NO_POST`

Symptom: transport failures hide under the wrong bucket and the queue misses them.
Cause: `report.ps1` maps `status -eq $null` to `NO_POST`; `-1` falls through to `other`.
Fix: treat `other` the same as `NO_POST` in the re-check queue; only `success`/`validated`/`closed` are verdicts.

## 39. Smoke passing while every row is a magic link

Symptom: `SMOKE PASS`, then 100 % of the batch is `link`; no hits, pool burned.
Cause: `smoke.ps1` counted only rows/403/429/407/unknown. `link` was a "valid" outcome.
Fix: smoke now fails on any link, requires >= 60 % `validated`, and requires a control login.

## 40. No control credential in the acceptance test

Symptom: the pipeline "passes" but nothing proves passwords are still compared.
Cause: the smoke list was fake addresses; a link or a fail-closed body can look like success.
Fix: pass `-Control` with a verified pair from `reference/STATE.md`; the control must log in with `zss`.

## 41. Falling back to the own widget without a gate

Symptom: every chunk burns 15 rows and produces link bodies; the run looks healthy in the totals.
Cause: `armWidget()` renders its own widget when the site one is missing, and the worker kept going.
Fix: worker records `widget_own` and aborts (`why:"widget-own"`) unless `ALLOW_OWN=1`; smoke fails on `armed=own:*`.

## 42. Counting a link batch as progress

Symptom: offset advances 90, queue grows by 90, hits stay 0.
Cause: link rows are records, so `run-all` advanced even though nothing was compared.
Fix: `run-all` stops when `link >= 80 %` of a batch (`FLOW-DEGRADED`) and leaves the offset decision to the operator.

## 43. Assuming the DOM contract is permanent

Symptom: `[data-hcaptcha-widget-id]` disappears; only `api.js?render=explicit` remains.
Cause: Yelp changed the page on 2026-11-20; the widget is now created later, by the submit flow.
Fix: check the contract before every pass (`probe-flow.ps1`), not just at build time. Contract drift is an incident,
not a tuning problem.
