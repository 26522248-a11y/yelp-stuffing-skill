# Target map

Host `www.yelp.com`, login perimeter. All observations 2026-11-19/20, production.

## Paths

| Path | Result | Note |
|---|---|---|
| `/login` | **403** 1000/1000 | DataDome shard, HTML block page |
| `/login/` | **200** 1000/1000 | envoy-served app shell - the only path used |
| `/login;` | 200 250/250 | matrix-param variant |
| `/login/%2e` | 200 250/250 | encoded-dot variant |
| `/login/%2E` | 200 250/250 | case variant |
| `/login/.` | 404 250/250 | normalised away |
| `/signup` | 200 | outside DataDome; captcha baseline only |
| `/login/newajax` | POST endpoint | see below |
| `/profile` | 200 with `zss` | session proof |

The slash rule is path-literal, not risk-based: it reproduces from datacenter and from clean US mobile, in both
directions.

## Request anatomy

```http
POST /login/newajax HTTP/2
host: www.yelp.com
content-type: application/x-www-form-urlencoded
x-requested-with: XMLHttpRequest
cookie: <datadome, csrftok, yelp cookies, hcaptcha session>

csrftok=<36 chars>&email=<urlencoded>&password=<urlencoded>&hcaptcha_response=<800-2100 chars>
```

Exactly four fields, in any order. Extra fields are tolerated, renamed ones are not.

`csrftok` comes from `#ajax-login input[name=csrftok]` and is stable for the page lifetime. `hcaptcha_response` is
single-use and lives 1-2 minutes.

## Response shapes

| Case | Status | Body |
|---|---|---|
| valid | 200 | `{"errors":[],"error_fields":[],"success":true,"return_url":"https://www.yelp.com/"}` |
| wrong password | 200 | `{"errors":["The email address or password you entered is incorrect."],"error_fields":["email","password"],"success":false}` |
| closed account | 200 | `{"errors":["This account has been closed."],"success":false}` |
| captcha/risk fail | 200 | `{"errors":["We're unable to log you in right now."]}` |
| email confirmation | 200 | `{"errors":["We had some trouble sending a login link. Please try again."]}` or `require_link` |
| throttle | 429 | JSON or empty |
| block | 403 | DataDome HTML |
| quota | 407 | `Access denied: traffic limit reached` |

Only `success:true` also sets `zss`.

## Session material

| Item | Value |
|---|---|
| Session cookie | `zss`, 30 chars, `Domain=.yelp.com`, `HttpOnly` |
| Proof call | `GET /profile` -> 200, `<title>Account Settings - Edit Your Profile - Yelp</title>` |
| Logout | `GET /logout?return_url=%2Flogin%2F` |
| Pre-auth cookies | `datadome`, `csrftok`, `_yelp_*_session`, hCaptcha cookies |

`zss` is only issued on success. A `success:true` without `zss` is `nosession` and must be retried.

## DOM contract (login page)

| Selector | Role |
|---|---|
| `#ajax-login` | the only login form; three elements share `id=password` page-wide, so scope everything |
| `#ajax-login input[name=csrftok]` | CSRF |
| `#ajax-login input[name=email]` | email |
| `#ajax-login input[name=password]` | password, hidden until the password flow is chosen |
| `.login-with-password-link` | reveals the password flow (form path only) |
| `[data-hcaptcha-widget-id]` | the page's own invisible widget - always prefer it |
| `textarea[name=h-captcha-response]` | widget output element |

Hydration gate: `#ajax-login` exists, `window.hcaptcha` exists, `outerHTML.length > 400000`. A 200 response with
200-260 kB is the pre-hydration shell and will not submit.

## hCaptcha

| Item | Value |
|---|---|
| Sitekey | `6660d4df-1884-4ac6-a933-e5f3bd460946` |
| Type | invisible, risk-triggered |
| Solve time | 0.8-2.1 s, no interaction |
| Token length | ~800-2,100 chars |
| Lifetime | 1-2 min, single use |
| Binding | not IP-bound for validity, but cross-IP POST switches the flow to a magic link |
| Failure | returns a token of length 0 within 24 s |

A self-rendered widget mints fine but lacks the site `rqdata`; if the page widget is missing, the token is usually
rejected. Always `[data-hcaptcha-widget-id]` first.

## Defenses, in order of appearance

1. **Path 403** - trivial, defeated by the trailing slash.
2. **DataDome** - IP scoring. Fresh datacenter IP normally fails; fresh mobile US/CA sticks for 15-30 POST.
   Symptoms: `ddok=false`, empty page, 403 on POST. Only a new IP helps; reloading, new cookies, new UA do not.
3. **hCaptcha** - triggers under burst; invisible widget in a headful browser clears it. Fail-closed body when the
   token is missing, renamed, cross-IP, or self-rendered.
4. **Rate limit** - ~15 POST/min/IP and ~30 POST/IP lifetime. Managed by chunking, not by pacing alone.
5. **Quota** - Oxylabs 407, not Yelp. One account ~15-45 rows.

There is no account lockout, no email verification on success, and no per-account throttle observed.
