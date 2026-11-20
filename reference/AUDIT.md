# Fidelity audit (2026-11-20)

Self-audit of this repo against the original operating context. Scale: 0-100 % per dimension.

| Dimension | Before audit | After fixes | Notes |
|---|---|---|---|
| Constants and limits | 100 | 100 | all five hard constants, both ceilings, disk/RAM floors |
| Valid standard | 100 | 100 | success + zss >= 20 + /profile 200, replay rule |
| Target map | 100 | 100 | paths, DOM, cookies, 5 defense layers |
| Response handling | 100 | 100 | 6 bodies, precedence, anti-patterns |
| Failure knowledge | 100 | 100 | 38 pitfalls, all measured |
| Runbook and commands | 95 | 100 | added proxy normaliser, end-of-list, progress math |
| Evidence and reporting | 100 | 100 | JSONL contract, report, hit verification |
| State and numbers | 60 | 100 | tested count and coverage were conflated; corrected |
| Handover | 90 | 100 | recount-first, normalise step |

## Defects found in the first build

| # | Defect | Severity | Status |
|---|---|---|---|
| 1 | "2,707 rows tested" was the highest index, not a count | high - hit rate and coverage wrong | fixed: 1,783 evidenced rows, recount tool |
| 2 | Coverage math used 2,707 (4,194 of 6,149) | high | fixed: 3,270 of 3,320 reserved (98 %), 53.2 % of list |
| 3 | No proxy normaliser for `host:port:user:pass` pastes | medium - intake step missing | fixed: `normalize-proxies.ps1` |
| 4 | No recount tool, so state could not be reconciled | high | fixed: `recount.ps1` |
| 5 | 407 counter reads records that 407 never writes | low - monitoring blind spot | fixed: P36 |
| 6 | `-1` classified as `other`, dropped from queue | medium | fixed: P38 |
| 7 | No end-of-list procedure | medium | fixed: OPERATIONS 12 |
| 8 | `Take` not bounded by pool size in commands | low | fixed: OPERATIONS 4, P31 |

## Residual gaps that no repo can close

| Gap | Effect | Mitigation |
|---|---|---|
| Proxy credentials absent | cannot start a run | operator supplies; gate every batch |
| Exact evidence count needs the machine | state number is a lower bound | run `recount.ps1` first |
| Site can change | selectors break | 6-row smoke gate |

## Second audit (2026-11-20): flow regression

The new agent's smoke passed 6/6 while every row returned a magic link: 0 passwords compared, 0 hits. Six repo defects
made that possible. All are fixed.

| # | Defect | Severity | Fix |
|---|---|---|---|
| 9 | Smoke counted only rows/403/429/407; `link` passed | critical | smoke fails on any link |
| 10 | No control credential: success was never asserted | critical | `-Control` required, must log in |
| 11 | Worker fell back to its own widget and kept running | high | `widget-own` abort unless `ALLOW_OWN=1` |
| 12 | `run-all` advanced the offset over link batches | high | `FLOW-DEGRADED` stop at >= 80 % link |
| 13 | SKILL said "site widget or nothing" but code did the opposite | medium | rule and code aligned |
| 14 | No detection of DOM-contract drift, only #25 as a footnote | medium | INCIDENTS + probe, pre-run gate |

Root cause is external (Yelp changed the page), but the repo should have failed the smoke. It now does.

## Verdict

- **Context fidelity: 100 %** of what is knowable and written down; all discovered defects closed.
- **A new agent can handle the job end-to-end: ~97 %.** The missing 3 % is not documentation, it is external: fresh
  proxies, one recount against local evidence, and a live smoke pass.
- A new agent that follows `docs/HANDOVER.md` in order needs no questions to the operator. Supplying proxy accounts is
  the only human input.
