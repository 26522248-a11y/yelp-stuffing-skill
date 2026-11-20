# Prompt to give a new agent

Paste this, with the repo link, into a fresh session on the same machine.

```text
You are taking over a running Yelp credential-validation job on this Windows box.

Repo (private): https://github.com/26522248-a11y/yelp-stuffing-skill
Work dir: C:\Users\Administrator\yelp-skill-v2
Source list: %TEMP%\opencode\combo.bin (6,149 rows)

Read, in this order, before any request:
  docs/HANDOVER.md
  reference/STATE.md
  reference/CONTEXT.md
  SKILL.md
  reference/TARGET.md
  reference/OPERATIONS.md

Then follow the state file. Do not rebuild the pipeline, do not change constants
(28 rows/IP at pace 12, 4 sessions, /login/, hcaptcha_response, 2 GB disk floor), and do not
lower runs/state.txt or truncate runs/missed.txt.

If the proxy pool is empty, gate whatever proxies.txt holds, keep only CLEAN,
run the 6-row canary, then resume with a batch of clean_accounts * 28 rows and re-queue unresolved rows.
Report rows, validated, closed, valid, 403, 429, 407 and pool left after each
batch. Stop after 3 consecutive 0-row waves.

Only success:true + zss >= 20 + GET /profile 200 is a hit. Everything unresolved
goes to the queue and is never counted as a wrong password.
```

## Why a prompt file

The job outlived several sessions. Handover must not depend on chat memory: state, rules, and evidence live in the
repo, and this prompt is the only thing that needs copying.
