# Runbook — GembaScan account login (status: ENABLED 2026-06-06)

> **UPDATE 2026-06-06 — login is now ENABLED.** `ACCOUNT_ENABLED=true` (backend) +
> `NEXT_PUBLIC_IS_ACCOUNT_SUPPORTED=true` (frontend) + reCaptcha key restored. Login is
> handled by **Auth0** (`/auth/auth0` → `gembachain.eu.auth0.com`, verified 302). The
> **csrf-stub Apache workaround was REMOVED** (it was only for the account-off state).
>
> **Correction:** login does NOT need SendGrid — per Blockscout docs, **login = Auth0**;
> **SendGrid is only for watchlist *notification* emails** (`ACCOUNT_SENDGRID_*`, now also
> configured with the `gembascan.io` authenticated domain, sender `no-reply@gembascan.io`).
> The earlier "email-code via SendGrid blocks login" note was a misdiagnosis.
>
> **Known background quirk:** for *logged-out* users `/api/account/v2/get_csrf` returns 401,
> and the frontend's `/api/csrf` route 500s on any non-200 — a cosmetic background error
> until the user logs in (then get_csrf returns 200 with the token). Does not block the
> Auth0 login flow.

> Historical notes below (the path we took to get here) are kept for reference.

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
| **reCAPTCHA v2** | ⚠️ configured but flaky | Blockscout 2.x supports **only v2 (not v3, not Turnstile)**. Keys in `.env` (`RE_CAPTCHA_*`), domains `testnet.gembascan.io`+`gembascan.io`. Key is valid, but the in-page "Continue with email" widget throws a **"reCAPTCHA initialization error"** in real browsers (Blockscout frontend bug; scripts load fine). The **Auth0 redirect (`/auth/auth0`) bypasses it**. |
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
