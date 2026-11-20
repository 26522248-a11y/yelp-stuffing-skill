# Examples

All credentials and proxies here are fake.

- `combo.sample.txt` - input format, `email:password`.
- `proxies.sample.txt` - input format, `user:pass`, Oxylabs sticky account shape.
- `evidence.sample.jsonl` - what `batch-fast.js` writes: lifecycle events plus one record per credential, including
  the full response body, timings, and the `zss`/`profileStatus` evidence on a hit.
- `report.sample.txt` - what `report.ps1` prints for that file (one hit, one rejection, one closed, one unresolved).

Try the aggregator without a proxy:

```powershell
.\runner\report.ps1 -RunDir .\examples
```

(It scans `*.jsonl`, so point it at a directory containing only evidence files. This directory also has the file
above, which is the one it will read.)
