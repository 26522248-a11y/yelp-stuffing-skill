# Checklists

## Pre-run

- [ ] No `node` or `chrome` process running
- [ ] `%TEMP%\cdp-*` empty
- [ ] Disk >= 2 GB
- [ ] Node >= 22, Chrome path resolves
- [ ] `state.txt` read (3320 expected, do not edit)
- [ ] `missed.txt` read (1487 expected, do not truncate)
- [ ] `proxies.txt` normalised to `user:pass`, deduplicated
- [ ] `check-proxy.ps1` run; >= 2 CLEAN
- [ ] `probe-flow.ps1` exit 0 (independent of smoke)
- [ ] `smoke.ps1 -Control <verified pair>` PASS: 0 link, >= 4 validated, armed=site

## Per-batch

- [ ] Batch size <= (clean accounts / 2) * 15
- [ ] `-Chunk 15 -Workers 2`
- [ ] Wave lines read as they appear
- [ ] 403/429/407 counted, not ignored
- [ ] `link` count 0; if >= 80 % of the batch, stop
- [ ] Any hit verified in-record (`success`, `zssLen >= 20`, `profileStatus 200`)

## Post-batch

- [ ] Nodes/chrome stopped, profiles deleted
- [ ] `progress.jsonl` line has non-zero rows or the wave was logged dead
- [ ] New hits appended to `VALID_ALL.txt` and `STATE.md`
- [ ] Queue count unchanged or reconciled
- [ ] Report sent with rows, verdicts, hits, 403/429/407, pool left

## Flow incident

- [ ] `armed` value in the JSONL starts with `site:`
- [ ] 0 `link` in smoke and in batch
- [ ] control pair logged in (`success` + `zss` >= 20)
- [ ] probe result recorded in `runs/probe`

## Hit verification

- [ ] `success:true` in the record
- [ ] `zssLen >= 20`, domain `.yelp.com`
- [ ] `profileStatus: 200`
- [ ] Replay on a fresh session reproduces `success` + a new `zss`
- [ ] `GET /profile` with that jar returns 200
- [ ] Pair written once, exactly as sent

## Shutdown / handover

- [ ] Processes stopped, disk cleaned
- [ ] `state.txt` and `missed.txt` intact
- [ ] `report.ps1` run
- [ ] Stats written where the next agent reads them
- [ ] Pool status recorded (clean/dirty/quota counts)
