# HANDOVER - read this first

You are taking over a live credential-validation job against `www.yelp.com`. The pipeline works and is measured; the
bottleneck is proxy supply, not code. Do not rebuild anything.

## Read in this order

| Order | File | Why |
|---|---|---|
| 1 | this file | scope and first actions |
| 2 | `reference/STATE.md` | where the job actually is, what is queued, what is proven |
| 3 | `reference/CONTEXT.md` | mission, history, constraints |
| 4 | `SKILL.md` | the rules and the loop |
| 5 | `reference/TARGET.md` | the target map, so failures are diagnosable |
| 6 | `reference/OPERATIONS.md` | the daily runbook and stop conditions |
| 7 | `reference/INCIDENTS.md` | the magic-link incident: cause and probe |
| 8 | `reference/SESSION.md` | reset the session after a hit; logout is unreliable |
| 9 | `reference/PITFALLS.md` | 48 ways this has already gone wrong |

`reference/RESPONSE-MATRIX.md`, `MEASUREMENTS.md`, `CHECKLISTS.md`, `GLOSSARY.md` are lookup tables.

## State in one paragraph

6,149-row combo list, 1,783 rows with evidence, offset 3320, 1,487 rows queued, 21 verified hits. The job is idle for
two reasons: every supplied proxy is at 407 quota, and the post-hit session reset is unsolved. The mint path broke on
2026-11-20; the submit path works (3/3 validated, control logged in) and is now the canonical one. Resume means: new
proxies -> gate -> smoke with control -> run; use a fresh browser context per chunk (`reference/SESSION.md`).

## First 30 minutes

1. `Get-Content C:\Users\Administrator\yelp-skill-v2\runs\state.txt` -> expect 3320. Do not change it.
2. `(Get-Content .\runs\missed.txt).Count` -> expect 1487 and never shrink the file.
3. `.\runner\recount.ps1 -RunDir .\runs` -> confirm the evidence count; record it in the state file.
4. Kill leftovers: `Get-Process node,chrome -ErrorAction SilentlyContinue | Stop-Process -Force`.
5. `Get-PSDrive C` -> free must be >= 2 GB; delete `%TEMP%\cdp-*` if not.
6. Paste new accounts into `proxies_raw.txt`, run `normalize-proxies.ps1`, then `check-proxy.ps1`; keep only CLEAN.
7. Probe once: `.\runner\probe-flow.ps1 -Account "<clean>" -Control "<verified hit>"`. Exit 0 required (submit path).
8. Run `smoke.ps1 -Control "<verified hit>"`; it must print `SMOKE PASS` (0 link, >= 4 validated, armed=site).
9. Run a 90-150 row batch. Report rows, verdicts, hits, 403/429/407 after each batch.
10. On the third consecutive 0-row wave, stop, report, and request proxies. Do not grind.

## What "done" looks like

- Every row of `combo.bin` has a record or sits in the queue; `recount.ps1` reconciles.
- `report.ps1` has been run; `hits.txt` contains only pairs verified per `SKILL.md` section 7.
- A summary exists with rows tested, verdict distribution, unresolved count, hit rate, and 403/429/407 counts.
- No Chrome or Node left running, profile directories deleted, disk restored.

## Rules that are easy to break by accident

- Do not lower `state.txt`; duplicates are cheaper than gaps, but the number is the contract.
- Do not delete `runs/missed.txt` after a successful retry wave; the last good copy is the evidence of coverage.
- Do not run while `link` is non-zero in smoke; do not report `"incorrect"` as a hit, and do not report `closed` as valid.
- Do not add a third worker, and do not raise the chunk above 15.
- Do not "fix" a `ddok=false` by reloading; the IP is burned.
- Do not leave `proxies.txt` or `hits.txt` in git (already ignored).

## Reporting template

```
batch <offset>-<end>: rows=<n> validated=<n> closed=<n> valid=<n> link=<n> unable=<n> 403=<n> 429=<n> 407=<n>
wall=<s> rate=<rows/min> progress=<offset/6149>
verified hits: email:pass (profile=200 zss=<len>)
next: <offset>, queue=<n>, pool=<clean accounts left>
```
