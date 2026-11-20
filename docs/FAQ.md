# FAQ

**Why not `curl` or `requests`?**
DataDome scores the TLS/HTTP fingerprint and needs a JS runtime. Plain HTTP clients get 403 or a shell. The only
reliable client is a real Chrome.

**Why not Playwright/Puppeteer?**
They add a dependency and a second automation surface. The runner drives CDP directly over `WebSocket`, which is
already in Node 22, and the relay is 30 lines. Fewer moving parts, no version drift.

**Why headful?**
The invisible widget is tied to a real rendering context and a real `rqdata`. Headless gets challenged more and the
site widget is often missing.

**Why mobile proxies?**
DataDome scores datacenter ranges heavily. Fresh mobile US/CA IPs survive 15-30 POST; datacenter often fails the first
one.

**Why exactly 15 rows?**
Two measured ceilings: 429 at ~16 POST/min and 403 at ~32 POST/IP. 15 gives margin under both and removes the need for
pacing sleeps on clean pools.

**Why relaunch Chrome per chunk instead of switching the proxy?**
Destroying the relay tunnel under a live Chrome leaves its network service unable to reconnect; four fresh IPs in a row
then fail to hydrate. A relaunch costs 15-25 s and always works.

**Can the captcha be skipped?**
It is invisible and solves itself in 0.8-2.1 s; a solver adds latency and a bill. Capsolver dropped hCaptcha in 2026.

**Why is a `success:true` not automatically a hit?**
Without `zss` there is no session. `nosession` happens on races and must be replayed.

**What does `closed` mean?**
The email exists but the account is deactivated. Intelligence, not a hit.

**Why does the same account appear in several runs?**
Accounts are not locked out. The limit is per IP, not per account, so a hit can be replayed for verification.

**How do I scale beyond 30 rows/min?**
More clean IPs, not more browsers. Two workers already saturate 4 GB RAM; each extra IP adds ~15 rows.

**How many accounts per pass?**
About one per 15-45 rows. A 30-account pool is one 300-450 row pass; expect 407 after that.

**Why keep `missed.txt` if rows are re-run anyway?**
It is the coverage ledger. Without it, tested + queued no longer reconciles with the list and the final rate is wrong.

**What if Yelp changes the page?**
Run `smoke.ps1`. If it fails twice, re-inspect selectors with a single manual browser and compare with
`reference/TARGET.md`; the fragile parts are listed there.
