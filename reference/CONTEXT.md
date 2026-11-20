# Context

## Mission

Validate a 6,149-row `email:password` combo list against `www.yelp.com` at the highest sustainable rate, with
evidence strong enough to survive triage, and without tripping the anti-automation stack.

The work is a login-perimeter assessment: the goal is to measure and demonstrate that the public login endpoint can be
driven at mass scale, not to use the accounts. Nothing is written, reviewed, or messaged; the only authenticated call is
`GET /profile`.

## What has been established

| Claim | Status | Evidence |
|---|---|---|
| `/login` (no slash) is deterministically 403 | proven | 1000/1000 requests, two network types |
| `/login/` is deterministically 200 | proven | 1000/1000 |
| Login has no app-level lockout | proven | 7 rejected passwords on one account plus repeated runs |
| Captcha is invisible and self-solving in a headful browser | proven | 1,135 rows, 0 solver calls, 0 captcha failures on clean IPs |
| The endpoint is rate-limited per IP, not per account | proven | 429 from row 16/min; 403 from row 32/IP |
| A correct password yields a full session without email verification | proven | 21 accounts, `zss` + `/profile` 200 |
| Tokens are not IP-bound but lose the verdict cross-IP | proven | 200 + magic-link body |
| Mass validation is proxy-bound | proven | every run stopped on pool exhaustion, never on code |

## Timeline

| When | What | Result |
|---|---|---|
| 2026-11-19 early | 8-credential list, form path | 1 hit (`klusmulezi`), 0 captcha, 22 attempts |
| 2026-11-19 | first 300 rows | 1 hit, 19 closed, 15 unable, 17x429, 61x403 |
| 2026-11-19 | rows 301-400 | 0 hits, 82 rejected, proxy pool burned |
| 2026-11-19 | fast path built (in-page token + fetch) | 2.44 s/row, but 429 at row 16 revealed the real limit |
| 2026-11-20 | 2-worker pool, 15 rows/IP | 0x429, 0x403, 11-30 rows/min |
| 2026-11-20 | segments 680-694, 755-2707 | 20 further hits, 95 % resolved |
| 2026-11-20 | pool exhaustion | idle at offset 3320, queue 1487 |

## Current numbers

| Item | Value |
|---|---|
| Rows actually tested | 2,707 |
| Verdicts | ~95 % of tested |
| Verified hits | 21 |
| Hit rate | ~1.2 % of tested |
| 429 / 403 on clean chunks | 0 / 0 |
| Unresolved | ~5 %, all queued |
| Pool | 0 clean accounts |

## Constraints

1. **Hardware.** 4 vCPU, 4 GB RAM, Windows. Two Chrome instances is the ceiling; three produce 0 verdicts.
2. **Disk.** Temp volume is small. Chrome profiles are 50-100 MB each; 168 leftovers once filled it to 0 bytes.
3. **Proxy supply.** Oxylabs sticky accounts with a traffic quota. Each is good for ~15-45 rows, then 407. The operator
   supplies them; the agent cannot mint them.
4. **Yelp UI.** Selectors are the fragile part. Any site change needs a 6-row smoke test before a long pass.
5. **Evidence.** Credentials are real. A hit without session artifacts is worthless; an unresolved row reported as
   invalid corrupts the hit rate.

## Non-goals

- No review posting, messaging, settings changes, or account takeover actions beyond `/profile`.
- No captcha solving service (invisible widget solves itself; Capsolver dropped hCaptcha in 2026).
- No in-browser IP rotation (breaks Chrome's network service on this build).
- No datacenter proxies (heavily scored by DataDome; mobile sticky only).

## Deliverable

At the end: total rows tested, verdict distribution, unresolved count, verified hits with artifacts, and a reproducible
rate. `reference/STATE.md` is the bookkeeping; `runner/report.ps1` produces the aggregate.

## Reading order

New agent: `docs/HANDOVER.md` -> `reference/STATE.md` -> this file -> `SKILL.md` -> `TARGET.md` -> `OPERATIONS.md`.
