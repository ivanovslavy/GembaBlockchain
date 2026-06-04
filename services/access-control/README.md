# access-control — off-chain PII/log backend (GDPR split)

The off-chain half of GembaBlockchain's workplace access control (CLAUDE.md §10).
It pairs with the on-chain `AccessControlNFT` (anonymous capability tokens):

- **On-chain (`contracts/src/access/AccessControlNFT.sol`):** a soulbound
  capability token per zone. Holding it means "this address may enter zone X".
  Only addresses and zone ids — **no PII, ever**. Immutable and verifiable.
- **Off-chain (here):** employee **identity (PII)**, the **identity → wallet/NFT
  bridge**, and all **access logs**. This is the real PII point, so it is guarded
  with **PostgreSQL Row-Level Security**, and it is **deletable** for the GDPR
  right to erasure — while the on-chain capability stays verifiable and anonymous.

## Why RLS

The app connects as the non-superuser role **`gemba_app`** (no `BYPASSRLS`), and
every request runs inside a transaction that sets `app.current_tenant`. The RLS
policies in [`db/schema.sql`](./db/schema.sql) (with `FORCE ROW LEVEL SECURITY`)
then make each institution able to read/write **only its own rows** — enforced by
the database, not by application filtering that a bug could bypass. This is the
guard on the identity → NFT bridge.

## GDPR right to erasure

`DELETE /employees/:id` (see [`src/gdpr.js`](./src/gdpr.js)):

1. revokes the employee's on-chain capabilities (`AccessControlNFT.revokeAccess`), then
2. deletes the off-chain PII + identity bridge + logs (schema cascades).

After erasure, any remaining on-chain token is **unlinked from any identity** —
de-identified — so personal data is gone while the chain stays immutable.

## API (devnet)

Each request carries `x-tenant-id` (a tenant UUID → drives RLS; in production from
an authenticated API key).

| Method | Path | Purpose |
|---|---|---|
| POST | `/employees` | register an employee (PII, off-chain) + wallet |
| POST | `/capabilities` | mint the anonymous NFT on-chain + record the mapping |
| POST | `/access-logs` | record a physical-access event (off-chain only) |
| GET | `/access/:wallet/:zone` | on-chain access check (address + zone only) |
| DELETE | `/employees/:id` | GDPR erasure (on-chain revoke + off-chain delete) |

## Run

```bash
npm install
npm test                       # unit tests (validation + GDPR logic), no DB needed

docker compose up -d           # local PostgreSQL with schema + RLS loaded
DATABASE_URL="postgres://gemba_app:devpassword@localhost:5432/gemba" \
  npm run test:integration     # proves RLS tenant isolation

# serve (needs DATABASE_URL, EVM_JSONRPC_HTTP, ACCESS_CONTROL_NFT_ADDRESS, ACCESS_ISSUER_PK)
npm start
```

## Secrets

The `ACCESS_ISSUER_PK` (the `ISSUER_ROLE` key that mints/revokes capabilities) and
DB credentials live in `.env` / a secret store, **never committed** (CLAUDE.md §3).
`node_modules/` is git-ignored.
