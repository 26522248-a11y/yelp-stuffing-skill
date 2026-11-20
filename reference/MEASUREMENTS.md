# Measurements

All rows observed on production `www.yelp.com`, 2026-11-19/20. Every rate comes from a recorded run; design targets are
marked as such.

## Throughput

| Configuration | Rows | Wall | Rows/min | 429 | 403 | Notes |
|---|---|---|---|---|---|---|
| 1 worker, 28-row budget paced 12/min | 28 | 155 s | 10.8 | 0 | 0 | 2.44 s/row |
| 1 worker, 50 rows un-paced | 50 | 278 s | 10.8 | 0 | 23 (from row 32) | IP cliff at 31 |
| 2 workers, 15-row chunks | 30 | 59 s | 30.5 | 0 | 0 | best observed |
| 2 workers, 15-row chunks | 30 | 93 s | 19.4 | 0 | 0 | typical |
| 2 workers, 90-row batches | 518 total | - | 11-13.5 | 0 | 0 | pool decayed late |
| 2 workers, 224-row segment | 224 | - | 12.2-13.3 | 0 | 0 | pool died before the last 3 batches |
| 2 workers, 336-row segment | 336 | - | 11-18.9 | 0 | 0 | 4 hits |
| 3 workers | 26 | 482 s | 3.2 | 0 | 0 | 0 verdicts, RAM starvation |

Per-credential components (28-row run): `avgTokMs` 1506, `avgPostMs` 931.

## IP limits

| Limit | Value | Evidence |
|---|---|---|
| POST per rolling minute | ~15 | un-paced burst: rows 16-19 returned 429, then recovered |
| POST per sticky IP | ~30 | first 403 at row 32 |
| Re-hydration effect on reputation | none | 403 wall unchanged after re-hydrating at 15 and 30 |
| Token bound to solving IP | no | minted on A, POST on B: 200 but magic-link |
| Parallel Chrome | 2 | 3 workers: 26 rows / 482 s, 0 verdicts |

## Proxy pool

| Observation | Value |
|---|---|
| Accounts in one supplied pool | 30 |
| Accounts already at 407 on intake | 8 |
| Rows an account survived after quota ran low | 0-60 |
| Fresh-session 403 rate once pool was burned | 12 of 20 sessions |
| Dead waves at the end of a pass | 3 consecutive, ~317 s each |

407 is an Oxylabs quota error. The pool is consumed by rows, not calendar time; 30 accounts is roughly one 300-450 row
pass.

## Infrastructure

| Limit | Observed |
|---|---|
| Disk | 168 leftover profiles = 6.85 GB; free hit 0; Node threw ENOSPC and Chrome stalled |
| RAM | 4 GB total, 1.6 GB free with 3 Chrome |
| Mitigation | profile deleted on exit; `statfsSync` guard aborts below 2 GB; 3-dead-wave stop |

## Verdict distribution, one clean 518-row segment

| Category | Count |
|---|---|
| password rejected | 450 |
| account closed | 29 |
| valid with session | 9 |
| needs-email / magic link | 13 |
| unable to log in | 2 |
| other | 15 |
| 403 / 429 | 0 / 0 |
| resolved | 488 / 518 = 94.2 % |

Later 224-row segment: 208 rejected, 8 closed, 2 valid, 5 needs-email, 1 unable, 0/0, 13.3 rows/min.

Later 336-row segment: 282 rejected, 18 closed, 4 valid, 0 403, 0 429, 11-18.9 rows/min, then pool death.

## Hit rate

| Sample | Rows | Valid |
|---|---|---|
| first 300 | 300 | 1 |
| single 8-row list | 8 | 1 |
| chunk 680-694 | 15 | 3 |
| segment 755-1805 | 518 | 9 |
| segment 1805-2330 | 224 | 2 |
| segment 2330-2707 | 336 | 4 |

Aggregate 21 hits across 1,783 evidenced rows (1.18 %). Do not extrapolate from fewer than 300 rows; 3/15 is an outlier.

## Path determinism (3,250 HEAD/GET)

| Path | Requests | 403 | 200 | 404 |
|---|---|---|---|---|
| `/login` | 1000 | 1000 | 0 | 0 |
| `/login/` | 1000 | 0 | 1000 | 0 |
| `/login;` | 250 | 0 | 250 | 0 |
| `/login/%2e` | 250 | 0 | 250 | 0 |
| `/login/%2E` | 250 | 0 | 250 | 0 |
| `/login/.` | 250 | 0 | 0 | 250 |

Same from datacenter and clean US mobile: the rule is path-literal.

## Corrections made to earlier drafts

| Claimed | Reality |
|---|---|
| `newajax` has no rate limit | ~15 POST/min; 429 at row 16 un-paced |
| 3 workers scale throughput | 3 workers collapse on 4 GB RAM |
| 5.4 s/credential is the floor | 2.44 s fast path, 2.0-3.1 s clean chunks |
| Re-hydrating refreshes IP reputation | no effect; only a new IP helps |
| A success is any `success:true` | needs `zss` + `/profile` 200 |
| 15 rows/session is the budget | 15 rows/IP is the safe budget; the session is the IP |
