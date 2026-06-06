# Runbook — GembaScan account login (status: DISABLED, deferred)

> **Recorded decision (2026-06-06):** user login on GembaScan stays **DISABLED** until
> an **email-verification-code flow is added** — Blockscout sends a sign-up/login
> **verification code by email via SendGrid**, and without that mail provider the
> account can never become verified (so "Log in" cannot work). Enabling login =
> wiring SendGrid (the "email code" sender) + flipping the account flags back on.
> Everything else in the chain (Auth0, cloak key, reCAPTCHA, Postgres pool) is already
> done; **SendGrid / the email code is the one remaining blocker.**

> The per-user **login + personal API keys** feature of the self-hosted Blockscout
> explorer is **intentionally disabled** (2026-06-06). It works up to a point but the
> last step needs another external service (SendGrid, for the email verification code).
> The **Etherscan-compatible API works without it** (see bottom). This documents how far
> we got and how to finish.

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

**Fix (while account stays off):** do **not** set `NEXT_PUBLIC_RE_CAPTCHA_APP_SITE_KEY`
on the frontend. reCaptcha does nothing useful while account is off, so removing it loses
no working feature and stops the CSRF fetch (verified: 0 `/node-api/csrf` calls after the
change). **When you re-enable account (below), put the reCaptcha key back** in the same
step — account login needs it.

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
