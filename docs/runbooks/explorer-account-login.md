# Runbook — GembaScan account login (status: ✅ WORKING 2026-06-07)

> **Email-OTP login works end-to-end** (enter email → receive code → logged in → personal
> API keys available). It is the Blockscout passwordless-email flow, backed by **Auth0**
> (the OTP is generated/sent by Auth0, **not** by Blockscout's own SendGrid). Getting here
> required a chain of fixes across Blockscout, the explorer host, and the Auth0 tenant —
> recorded below so it can be reproduced for mainnet.

## ✅ The complete working recipe (every piece is required)

**1. Blockscout backend** (`/root/gembascan/envs/backend.env`, gitignored):
- `ACCOUNT_ENABLED=true`
- `ACCOUNT_AUTH0_DOMAIN=gembachain.eu.auth0.com` (bare — NO `https://`, NO trailing `/`)
- `ACCOUNT_AUTH0_CLIENT_ID` / `ACCOUNT_AUTH0_CLIENT_SECRET` (the Regular Web App)
- `ACCOUNT_SENDGRID_API_KEY` / `_SENDER=no-reply@gembascan.io` / `_TEMPLATE=d-…` (watchlist mail only)
- `RE_CAPTCHA_DISABLED=true`  ← **the reCAPTCHA workaround**, see step 2
- `RE_CAPTCHA_CHECK_HOSTNAME=false` (the Auth0/SendGrid origin check is enough)

**2. reCAPTCHA — Blockscout frontend bug, worked around.** Blockscout supports only
reCAPTCHA **v2 invisible**, but its frontend (`latest`/v2.3.5) `executeAsync()` never
produces a token here (confirmed via a server-side header capture: `recaptcha-v2-response`
arrives empty; reproduced in clean incognito on Chrome+Firefox, so NOT an extension/CSP/key
issue — the key is a valid v2-invisible key with the domains registered). So `send_otp`
got a 403 "Invalid reCAPTCHA response". **Workaround:** `RE_CAPTCHA_DISABLED=true` on the
backend so the empty token is accepted, **while KEEPING** `NEXT_PUBLIC_RE_CAPTCHA_APP_SITE_KEY`
set on the frontend — because removing it hides the whole email-login UI (leaves only
"web3 connect"). So: key present (UI shows) + backend ignores it (no 403).

**3. Auth0 tenant** (the app with the Client ID above). Login is Auth0; the OTP email is
sent by Auth0 → its SendGrid provider. Each of these was a separate blocker:
- **M2M / Management API:** `send_otp` needs a Management-API (M2M) token. Enable the app's
  **Client Credentials** grant AND authorize it on the **Auth0 Management API** (scopes incl.
  `read:users`,`create:users`,`update:users`,`read:user_idp_tokens`). Symptom if missing:
  backend log `Failed to get M2M JWT`; Auth0 `/oauth/token` returns
  `unauthorized_client: Grant type 'client_credentials' not allowed for the client`.
  (Authorizing on the Management API auto-enables the grant — easiest path.)
- **Passwordless Email connection** must be **enabled for this application** (it defaulted to
  0 enabled clients). API: `PATCH /api/v2/connections/{id}/clients` `[{client_id,status:true}]`.
- **Auth0 Email Provider = SendGrid**, with the SendGrid API key whose account has
  `gembascan.io` authenticated, and `default_from_address=no-reply@gembascan.io`.
- **THE final killer:** the passwordless **connection's email template `from` defaulted to
  `{{ application.name }} <root@auth0.com>`** → SendGrid 550 *"from address does not match a
  verified Sender Identity"* (visible only in **Auth0 tenant logs**, type `fn` =
  Failed-Sending-Notification). Fix: set the connection's `options.email.from` to
  `GembaScan <no-reply@gembascan.io>` (a sender on the SendGrid-authenticated domain).

**Best diagnostic:** Auth0 **tenant logs** (`GET /api/v2/logs`, scope `read:logs`) — type
`fn` carries the exact SendGrid error; `cls` = code/link sent. Blockscout's own log only
says the generic `Failed to get M2M JWT` / returns 200 once Auth0 accepts the request.

---

## Historical notes (the path we took) — kept for reference

## Why it's disabled

`ACCOUNT_ENABLED=false` (backend) + `NEXT_PUBLIC_IS_ACCOUNT_SUPPORTED=false` (frontend)
→ no "Log in" button, no SendGrid error spam, clean explorer. The Etherscan-style
API is unaffected.

## What the login feature needs (the dependency chain)

Self-hosted Blockscout account is a chain of external services — **all of these**:

| Piece | Status | Notes |
|---|---|---|
| **Auth0** (identity) | ✅ done | App MUST be **Regular Web Application** (not SPA). `ACCOUNT_AUTH0_DOMAIN/CLIENT_ID/CLIENT_SECRET` in `.env`. Callback `/auth/auth0/callback` (Apache routes `/auth`→backend). Tenant `gembachain.eu.auth0.com`. |
| **`ACCOUNT_CLOAK_KEY`** | ✅ done | Account DB encryption key (base64 32-byte). Was MISSING → callback 500 `aes_256_gcm "invalid key size"`. Now set in `.env`. |
| **reCAPTCHA v2 *invisible*** | ✅ root cause found 2026-06-06 | Blockscout frontend supports **ONLY reCAPTCHA v2 _invisible_ mode** (per frontend `docs/ENVS.md`: "we currently support only reCAPTCHA v2 invisible mode"). The earlier "reCAPTCHA initialization error" on the watchlist-email widget was NOT a Blockscout bug and NOT a domain/env problem — the configured key was a **v2 _Checkbox_** key (verified via Google's anchor endpoint: it rendered `rc-anchor`, and `testnet.gembascan.io` was a valid domain). A Checkbox key in an invisible-mode integration fails to initialize. **Fix: create a v2 _Invisible_ key** (google.com/recaptcha/admin/create → reCAPTCHA v2 → "Invisible reCAPTCHA badge"; domains `testnet.gembascan.io`+`gembascan.io`) and set it as `NEXT_PUBLIC_RE_CAPTCHA_APP_SITE_KEY` (frontend) + `RE_CAPTCHA_CLIENT_KEY`/`RE_CAPTCHA_SECRET_KEY` (backend). Login itself (Auth0 `/auth/auth0`) does not need it. |
| **Postgres** | ✅ done | Account adds a connection pool → bumped `max_connections=300` (was hitting `too_many_connections`). |
| **SendGrid** | ❌ MISSING — the blocker | Account requires **email verification**, sent via SendGrid. Not configured → on login the backend spams `RuntimeError: SendGrid not configured`, the account stays unverified, and `/api/account/v2/user/info` returns **403** → user appears not logged in despite a successful Auth0 callback. |

## Where we got to (the exact failure)

1. `/auth/auth0` (direct URL, fresh tab/incognito) → redirects to Auth0 Universal Login ✅
2. User logs in at Auth0 → callback `/auth/auth0/callback` → **302 success** (cloak key fixed the earlier 500) ✅
3. Browser redirected back to the explorer, BUT `/api/account/v2/user/info` → **403** (email not verified, no SendGrid) → **appears logged out** ❌

So: Auth0 + cloak + reCAPTCHA-config are done; the remaining gap is **email verification (SendGrid)** + the **flaky reCAPTCHA widget** (the Auth0-redirect path sidesteps the widget).

## ⚠️ Side effect while disabled — the CSRF / "HTTP 500" trap (fixed 2026-06-06)

With account **off** but `NEXT_PUBLIC_RE_CAPTCHA_APP_SITE_KEY` still set on the frontend,
the explorer threw an **HTTP 500 on ordinary browsing** (e.g. after searching an
address). Cause: a present reCaptcha site key turns on the reCaptcha-gated frontend
features (CSV export, public-tag submission), which fetch a CSRF token on page load via
`/node-api/csrf` → backend `/api/account/v2/get_csrf`. With `ACCOUNT_ENABLED=false` the
backend returns **404 "Account functionality is disabled"**, and the Next.js proxy
surfaces it as a **500**.

**What actually fixed it (2026-06-06).** Removing the reCaptcha key was NOT enough — the
frontend (`frontend:latest`, v2.3.5) fetches the CSRF token on every page regardless, via
the Next.js route `/api/csrf` → `general:csrf` → backend `/api/account/v2/get_csrf`. That
route's handler returns **HTTP 500 for ANY non-200 upstream** (the backend 404s with account
off). The 500 surfaces as a visible error on normal browsing (e.g. typing a CA in the search
box → 500 toast). The handler treats **200** specially: it just reads the `x-bs-account-csrf`
response header (absent when account is off → `{token:null}`) and returns 200. So the fix is
to make that one path return a **static 200** at the Apache layer:

```apache
# in gembascan-le-ssl.conf, BEFORE  ProxyPass /api ...
ProxyPass /api/account/v2/get_csrf !
Alias    /api/account/v2/get_csrf /var/www/gembascan-brand/csrf-stub.json   # file contains: {}
```

Verified: `/api/account/v2/get_csrf` → 200, `/node-api/csrf` → 200 (was 500), other
`/api/account/v2/*` still proxy to the backend, search/API unaffected. **⚠️ REMOVE this
Apache block when you enable account/login** (below), otherwise it shadows the real csrf
endpoint and login breaks. reCaptcha was also dropped from the frontend; re-add it WITH
account when login is enabled.

## How to finish later (for mainnet, if wanted)

1. Sign up for **SendGrid** (free tier), verify a sender, create an API key. Set in
   `envs/backend.env`: `SENDGRID_API_KEY`, `SENDGRID_SENDER`, (optional `SENDGRID_TEMPLATE`)
   and the `ACCOUNT_SENDGRID_*` equivalents.
2. Re-enable: `ACCOUNT_ENABLED=true` + frontend `NEXT_PUBLIC_IS_ACCOUNT_SUPPORTED=true`,
   recreate backend+frontend.
3. For the "Log in" **button** reCAPTCHA init bug: either accept the Auth0-redirect
   login (`/auth/auth0`, no widget), or patch the frontend / try a newer Blockscout.
4. All secrets are already in the gitignored `.env` (Auth0, cloak, reCAPTCHA v2).

## In the meantime — the API works WITHOUT login/keys

The Etherscan-compatible API needs no account/key (just a global rate limit):

```
https://testnet.gembascan.io/api?module=account&action=balance&address=0x…
```
`module=account|contract|transaction|block|logs|stats|token` — existing Etherscan
tooling works unchanged. Per-user API keys (higher limits) only come with the account
feature above.
