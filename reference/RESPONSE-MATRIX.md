# Response matrix

Raw shapes and how they are classified. Bodies are verbatim except truncated payloads.

## 200 - valid

```json
{"errors":[],"error_fields":[],"success":true,"return_url":"https://www.yelp.com/"}
```

Headers of interest:

```
set-cookie: zss=<30 chars>; Domain=.yelp.com; Path=/; HttpOnly; Secure
content-type: application/json; charset=utf-8
```

Class: `success`. Then: 2 s sleep, `GET /profile`, read cookies, logout, re-hydrate.

## 200 - wrong password

```json
{"errors":["The email address or password you entered is incorrect."],"error_fields":["email","password"],"success":false}
```

Class: `validated`. The server compared both fields. The email exists unless `error_fields` is email-only.

Variants seen: `"The email address or password you entered is incorrect. Please try again."`, and an email-only form
when the address is unknown. Both classify as `validated`, but only the pair-bearing one proves the email.

## 200 - closed account

```json
{"errors":["This account has been closed."],"success":false}
```

Class: `closed`. Email exists; the account is deactivated. Useful for the report, not a hit.

## 200 - captcha / risk fail-closed

```json
{"errors":["We're unable to log you in right now."]}
```

Class: `unable`. Nothing was compared. Causes: missing/renamed token, rejected token, cross-IP token, self-rendered
widget without `rqdata`, exhausted risk budget.

Distinguish from `validated` by the absence of `error_fields`.

## 200 - email confirmation / magic link

```json
{"errors":["We had some trouble sending a login link. Please try again."],"success":false}
```

or a body containing `require_link` / `magic_link`.

Class: `link`. The password was accepted but Yelp wants email confirmation. Most often caused by cross-IP token reuse.
Retry on a single clean IP before recording as `needs-email`.

## 429 - throttle

```text
Too Many Requests
```

Class: `429`. Per rolling minute, per IP. Runner sleeps 13 s and retries the same row, up to 3 attempts.

## 403 - DataDome

```html
<title>Access Denied</title>
... Reference #18.<hex> ...
```

Class: `403`. IP is spent. The current runner stops the chunk immediately: re-hydrating does not help.

## 407 - Oxylabs quota

```text
Access denied: traffic limit reached
```

Class: `407`. Account quota, not Yelp. Drop the account.

## -1 / empty body

`status:-1`, `body:"fetch:<message>"`, or a 200 with an empty body.

Class: `NO_POST` / `other`. Retry. Common causes: page not hydrated, Chrome network service dead, disk full.

## Classification precedence

`success > nosession > validated > closed > link > unable > 407 > 429 > 403 > NO_POST > other`

A later better record for the same email replaces an earlier one. Hits dedupe on the credential pair.

## Anti-patterns

| Pattern | Why it lies |
|---|---|
| Alert text in the DOM | the AJAX flow does not change `uniqueRequestId`; the old message persists |
| `Fetch.getResponseBody` on the login request | success navigates and the body is lost |
| Treating any 200 as a verdict | the empty shell returns 200 |
| Treating `unable` as wrong password | nothing was compared |
| Counting `success:true` without `zss` | no session was created |
