# Incident: auth flow flipped to magic-link (2026-11-20)

Status: **open**, list runs paused. One IP / two attempts observed.

## Symptom

| Signal | Value |
|---|---|
| Smoke | `SMOKE PASS` on the old criteria (6/6 rows, 0 403/429/407, 0 unknown) |
| Actually | 6/6 `link`, 0 `validated`, 0 `success` |
| Body | `"We need to confirm it's really you. We've sent an email with a login link"` |
| Token | minted fine, 1,880-1,970 chars, `tokFail=0` |
| HTTP | 200 on every POST |
| Page | hydrates to 1.49 MB, password field visible |
| DOM | `[data-hcaptcha-widget-id]` **absent**; only `api.js?render=explicit` |
| Worker | `armed:"own:..."` - self-rendered widget, no `rqdata` |

## Why it slipped through

`smoke.ps1` accepted rows + status only. `link` was not a failure, there was no control credential, and the worker
fell back to its own widget without gating. All three are now fixed.

## What is proven

- The site widget is gone from the initial DOM (probe 1: still absent after clicking the password link and filling).
- A self-rendered token still mints, but the server answers with email-confirmation instead of a verdict.
- This matches PITFALLS #25 at the token level, with a new, quieter response.

## What is NOT proven

- Whether the submit path (Yelp renders its own widget at submit time) still yields `validated`.
- Whether every IP behaves this way (2 IPs tried).

## Probe 2 (next, ~2 min, 1 IP, 1 credential)

```powershell
cd C:\Users\Administrator\yelp-skill-v2
.\runner\probe-flow.ps1 -Account "<clean proxy user:pass>" -Control "<verified hit email:pass>"
```

It submits one control credential through the real form, lets Yelp mint its own token, captures `/login/newajax` via
CDP, and prints `widget_presence`, `verdict`, `status`, `body`.

| Exit | Meaning | Action |
|---|---|---|
| 0 `validated` | password still compared on the submit path | port `batch-fast` to submit, then run |
| 0 `success` | control logged in | same |
| 1 `link` | flow is globally email-confirmation | stop; decide direction with the operator |
| 1 gate | account dirty | new account, retry once |
| 2 | crash/no result | read the JSONL in `runs/probe` |

## Decision tree

```text
probe 2 validated/success?
  yes -> submit-path worker -> smoke (control) -> resume list
  no  -> is the widget present after submit?
           yes -> token/rqdata issue confined to fetch path; port to submit anyway
           no  -> global magic-link flow: link rows prove email existence only
                  -> agree with operator whether to keep burning pool for closed/valid split
```

## If the flow is global

Consequences to state plainly:

- `link` proves the email exists, not the password.
- `validated` disappears; hit detection needs email access or a second signal.
- `closed` still works and is still useful.
- Value per IP drops hard: do not start a 150-row batch until the decision is made.

## Do not

- Do not run the list "to see". 15 proxies buy ~15 rows of the same link body.
- Do not tune pacing, UA, or workers. This is not a rate problem.
- Do not swap in a solver: the token is minted, it is the `rqdata` context that is missing.
