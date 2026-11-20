# Glossary

| Term | Meaning |
|---|---|
| **combo** | `email:password` line from a breach corpus |
| **stuffing** | replaying a combo list against a login endpoint |
| **valid / hit** | `success:true` + `zss` >= 20 + `/profile` 200 |
| **validated** | server compared the password and rejected it (`error_fields` includes `password`) |
| **closed** | email exists, account deactivated |
| **nosession** | `success:true` but no `zss` / `profile`; not a hit |
| **needs-email / link** | password accepted, email confirmation required |
| **unable** | captcha/risk fail-closed; nothing compared |
| **unresolved** | no verdict: link, unable, 403, 407, 429, -1, empty |
| **verdict** | success, validated, or closed |
| **ddok** | page passed DataDome and rendered the real login DOM |
| **hydrate** | page reached usable state: `#ajax-login`, `hcaptcha`, `outerHTML > 400k` |
| **mint** | `hcaptcha.execute` + poll `getResponse` for a token |
| **arm** | bind the page's widget id so `execute` works |
| **budget** | POST allowed per sticky IP (15) |
| **chunk** | 15-row unit = one IP = one Chrome = one account |
| **wave** | one chunk per worker, dispatched together |
| **batch** | `-Take` rows = 10 chunks = 5 waves |
| **sticky session** | `-sessid-<rand>-sesstime-1800` suffix pinning an IP |
| **gate** | health check of a fresh session; CLEAN only if 200 |
| **CLEAN / DIRTY / QUOTA / DEAD** | gate outcomes |
| **pool** | proxy account file/collection |
| **queue** | `missed.txt`, rows that produced no record |
| **offset** | next row in `state.txt` |
| **zss** | 30-char session cookie proving login |
| **CSRF** | `csrftok` field from `#ajax-login` |
| **rqdata** | hCaptcha site metadata; absent in self-rendered widgets |
| **relay** | local CONNECT proxy that injects Oxylabs auth |
| **CDP** | Chrome DevTools Protocol, used over WebSocket |
| **BID** | worker index; shifts the relay and CDP ports |
