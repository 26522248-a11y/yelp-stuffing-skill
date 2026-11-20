# yelp-stuffing-skill (private)

Operational skill for validating Yelp credentials at volume: DataDome path bypass, invisible hCaptcha solved inside a
real headful browser (no solver), 2-worker sticky-proxy pool, 15 credentials per IP, evidence-first verdicts.

Measured on production `www.yelp.com` (2026-11-19/20): **2.0-3.1 s per credential, 11-30 rows/min, 0x429, 0x403** on
clean 15-row chunks.

## What this repo is for

A fresh agent must be able to read this repo and continue the running job **without asking the operator anything**.
That means the repo carries not only the method, but the target map, the live state, the queue, the verified hits, the
failure catalogue, and the exact commands.

Start here: [`docs/HANDOVER.md`](docs/HANDOVER.md).

## Current job state (2026-11-20)

| Item | Value |
|---|---|
| Source list | `C:\Users\Administrator\AppData\Local\Temp\2\opencode\combo.bin` (6,149 rows) |
| Resumed offset | `runs/state.txt` = **3320** (real coverage 2,707; gap rows are queued) |
| Re-check queue | `runs/missed.txt` = **1487 rows** |
| Verified hits | **21** (see `reference/STATE.md`) |
| Proxy pool | **empty** — every supplied account is at 407 quota or burned |
| Next action | add proxies -> `check-proxy.ps1` -> resume |

## Quick start

```powershell
cd C:\Users\Administrator\yelp-skill-v2
.\runner\check-proxy.ps1 -Accounts (Get-Content .\proxies.txt)
.\runner\smoke.ps1 -PoolFile .\proxies.txt
.\runner\run-all.ps1 -Source "$env:TEMP\opencode\combo.bin" -PoolFile .\proxies.txt -Take 150 -Chunk 15 -Workers 2
.\runner\report.ps1 -RunDir .\runs -HitsFile .\hits.txt -OutCsv .\classified.csv
```

## Validity

`valid` = `success: true` **and** a `zss` cookie of >= 20 chars **and** `GET /profile` = 200. Nothing else counts.
`"incorrect"` is a server-compared rejection. `closed` proves the email exists. Link/unable/403/407/429 are unresolved,
never "invalid".

## Doc map

| File | Purpose |
|---|---|
| `SKILL.md` | the playbook: constants, loop, classification, failure playbook |
| `docs/HANDOVER.md` | onboarding order for a new agent; first 30 minutes |
| `reference/CONTEXT.md` | mission, scope, history, constraints, status |
| `reference/TARGET.md` | endpoint map, DOM, cookies, defense layers |
| `reference/RESPONSE-MATRIX.md` | every observed body/status and its meaning |
| `reference/OPERATIONS.md` | daily runbook, stop conditions, escalation |
| `reference/CHECKLISTS.md` | pre-run, per-batch, post-run, report |
| `reference/PITFALLS.md` | 35 failure modes, symptom -> cause -> fix |
| `reference/MEASUREMENTS.md` | measured rates, limits, corrections |
| `reference/STATE.md` | live offset, queue, hits, proxy status |
| `reference/GLOSSARY.md` | terms used in this repo |
| `docs/ARCHITECTURE.md` | worker sequence, ports, where each failure lands |
| `docs/NEW-AGENT-PROMPT.md` | ready-to-paste handover prompt |
| `docs/FAQ.md` | design questions answered |
| `runner/README.md` | script usage and exit codes |
