# yelp-stuffing-skill

> **2026-11-21 correction - the fast path works.** The magic-link incident was an **exit-IP** problem, not missing
> `rqdata`: Yelp's own `hCaptcha.render` passes no `rqdata`, and a self-rendered token validates 28/28 on a clean IP.
> Canonical runbook: **https://github.com/26522248-a11y/yelp-auth-runbook** (`docs/00-START-HERE.md`).
> Everything below that calls the mint/fast path "deprecated" or the submit path "canonical" is historical.

Operational skill for validating Yelp credentials at volume: DataDome path bypass, invisible hCaptcha solved inside a
real headful browser (no solver), sticky-proxy pool, 28 credentials per IP at pace 12, evidence-first verdicts.

Measured on production `www.yelp.com` (2026-11-19/21): **2.0-3.1 s per credential, 11-30 rows/min per worker,
0x429, 0x403** on clean 28-row chunks.

## What this repo is for

A fresh agent must be able to read this repo and continue the running job **without asking the operator anything**.
That means the repo carries not only the method, but the target map, the live state, the queue, the verified hits, the
failure catalogue, and the exact commands.

Start here: **https://github.com/26522248-a11y/yelp-auth-runbook** (`docs/00-START-HERE.md`), then
[`docs/HANDOVER.md`](docs/HANDOVER.md) as the historical onboarding note.

## Current job state (2026-11-20)

| Item | Value |
|---|---|
| Source list | `C:\Users\Administrator\AppData\Local\Temp\2\opencode\combo.bin` (6,149 rows) |
| Resumed offset | `runs/state.txt` = **3320** (rows with evidence 1,783; gap rows queued) |
| Re-check queue | `runs/missed.txt` = **1487 rows** |
| Verified hits | **21** (see `reference/STATE.md`) |
| Proxy pool | **empty** ÃÂÃÂ¢ÃÂÃÂÃÂÃÂ every supplied account is at 407 quota or burned |
| Next action | add proxies -> gate -> 6-row canary -> fast path at 28 rows/IP, pace 12 (see the runbook) |

## Quick start

```powershell
cd C:\Users\Administrator\yelp-skill-v2
.\runner\check-proxy.ps1 -Accounts (Get-Content .\proxies.txt)
.\runner\smoke.ps1 -PoolFile .\proxies.txt
.\runner\run-all.ps1 -Source "$env:TEMP\opencode\combo.bin" -PoolFile .\proxies.txt -Take 150 -Chunk 28 -Workers 4
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
| `reference/PITFALLS.md` | 38 failure modes, symptom -> cause -> fix |
| `reference/MEASUREMENTS.md` | measured rates, limits, corrections |
| `reference/STATE.md` | live offset, queue, hits, proxy status |
| `reference/GLOSSARY.md` | terms used in this repo |
| `docs/ARCHITECTURE.md` | worker sequence, ports, where each failure lands |
| `docs/NEW-AGENT-PROMPT.md` | ready-to-paste handover prompt |
| `docs/FAQ.md` | design questions answered |
| `runner/README.md` | script usage and exit codes |
| `reference/INCIDENTS.md` | magic-link incident: cause, probe, decision tree |
| `reference/SESSION.md` | reset session after a hit; why logout fails |
| `reference/AUDIT.md` | fidelity audit, defects found and closed |
