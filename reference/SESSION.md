# Session reset after a hit

Problem: post-login, `/login/` redirects to `/`, so the next credential has no form. Logout is unreliable and cookie
deletion from CDP does not end the session. This file records what was tried and the fix.

## What was tried and failed

| Attempt | Result |
|---|---|
| `GET /logout?return_url=%2Flogin%2F` | 200, session alive |
| `POST /logout` | 200, session alive |
| `GET /logout/` | 200, redirect to `/`, session alive |
| `Network.deleteCookies zss` | 200 on `/profile` afterwards |
| `Network.clearBrowserCookies` | 200 on `/profile` afterwards |
| `Storage.clearDataForOrigin` | 200 on `/profile` afterwards |

## Why "still 200" misleads

1. **The page is in memory.** A logged-in document keeps its JS state; `fetch('/profile')` from that document is not a cold request.
2. **Cookies come back.** The front end re-issues session cookies on the next XHR; one `/profile` call can restore what you deleted.
3. **deleteCookies needs the exact tuple**: name, domain (`.yelp.com`), path, secure. A bare name matches nothing.
4. **HTTP cache.** `/profile` can be served from disk cache unless `Network.setCacheDisabled(true)`.
5. **`zss` may not be the auth cookie.** Session may live in `_yelp_session`, `ycs`, another HttpOnly cookie, or
   localStorage / IndexedDB. Deleting `zss` alone proves nothing.
6. **Logout is state-changing**: it likely needs `csrftok` and `X-Requested-With: XMLHttpRequest`, or the bare
   `yelp.com` host. A bare GET just renders `/`.

## Fix 1 - fresh browser context (recommended)

CDP gives an isolated cookie/storage partition inside the same Chrome: logged out, same IP, no relaunch.

```js
const bc = await send('Target.createBrowserContext', { disposeOnDetach: true });
const ctx = bc.result.browserContextId;
const nt = await send('Target.createTarget', { url: 'https://www.yelp.com/login/', browserContextId: ctx });
const at = await send('Target.attachToTarget', { targetId: nt.result.targetId, flatten: true });
// use at.result.sessionId for the chunk; on hit:
await send('Target.disposeBrowserContext', { browserContextId: ctx });
```

Caveat: a new context loses the `datadome` cookie and can raise the challenge rate. If `ddok=false` climbs, keep one
context for the whole chunk and only recreate it after a hit, never mid-chunk.

## Fix 2 - logout with CSRF (only if contexts fail)

```js
const tok = await ev('(function(){var i=document.querySelector("input[name=csrftok]");return i?i.value:"";})()');
await ev('fetch("/logout",{method:"POST",credentials:"include",headers:{"Content-Type":"application/x-www-form-urlencoded","X-Requested-With":"XMLHttpRequest"},body:"csrftok="+encodeURIComponent(' + JSON.stringify(tok) + ')})');
```

Then verify cold: `Network.clearBrowserCache`, `Page.navigate('/login/')`, require `#ajax-login`.

## Fix 3 - accept the cut (fallback)

A hit ends the chunk; the next chunk gets a new IP. A hit lands uniformly in a 15-row chunk, so ~7 rows are wasted per
hit. At 1.2 % that is ~8.4 % extra proxy burn and ~12 extra relaunches per 1,000 rows. Slow, predictable, never
corrupts a verdict.

## Find which cookie actually holds the session

```js
const names = async () => (await sendS('Network.getAllCookies')).result.cookies.map(c => c.name + '@' + c.domain);
const before = await names(); ... const after = await names();
// names only in `after` are the session candidates; write the diff into the JSONL
```

Until the name is known, a hit gate of `success:true` + `/profile:200` is enough. Keep `zssLen` as a signal, not as the
only condition.

## Cold-state check (never trust a live document)

```text
1. Network.setCacheDisabled true
2. delete cookies with explicit domain .yelp.com
3. Page.navigate /login/   (not fetch)
4. #ajax-login present -> logged out; absent -> still logged in
```
