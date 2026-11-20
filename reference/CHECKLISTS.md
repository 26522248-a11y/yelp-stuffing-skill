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
- [ ] `smoke.ps1` PASS

## Per-batch

- [ ] Batch size <= (clean accounts / 2) * 15
- [ ] `-Chunk 15 -Workers 2`
- [ ] Wave lines read as they appear
- [ ] 403/429/407 counted, not ignored
- [ ] Any hit verified in-record (`success`, `zssLen >= 20`, `profileStatus 200`)

## Post-batch

- [ ] Nodes/chrome stopped, profiles deleted
- [ ] `progress.jsonl` line has non-zero rows or the wave was logged dead
- [ ] New hits appended to `VALID_ALL.txt` and `STATE.md`
- [ ] Queue count unchanged or reconciled
- [ ] Report sent with rows, verdicts, hits, 403/429/407, pool left

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
