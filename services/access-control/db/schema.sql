-- =============================================================================
-- GembaBlockchain access-control backend — schema + Row-Level Security (RLS)
-- =============================================================================
-- This is the OFF-CHAIN half of the GDPR split (CLAUDE.md §10):
--   * On-chain  : anonymous capability NFTs (address holds zone token). No PII.
--   * Off-chain : employee identity (PII), the identity -> wallet/NFT bridge, and
--                 all access logs. THIS is the real PII point; it is guarded with
--                 PostgreSQL Row-Level Security so each institution (tenant) can
--                 only ever read/write its own rows, and so PII is deletable for
--                 the GDPR right to erasure while the on-chain capability stays
--                 verifiable and anonymous.
--
-- The app connects as a NON-superuser role (gemba_app) so RLS is enforced, and
-- sets `app.current_tenant` per request; every policy keys on it.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

-- Application role (no BYPASSRLS, not superuser): RLS always applies to it.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gemba_app') THEN
    CREATE ROLE gemba_app LOGIN;
  END IF;
END $$;

-- --- Tenants (institutions). Not tenant-scoped themselves. ---
CREATE TABLE IF NOT EXISTS tenants (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- --- Employees: PII lives here and ONLY here (off-chain, deletable). ---
CREATE TABLE IF NOT EXISTS employees (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  full_name   text NOT NULL,         -- PII
  email       text,                  -- PII
  wallet      text NOT NULL,         -- the identity -> address bridge (0x...)
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, wallet)
);

-- --- Capabilities: the identity -> on-chain NFT mapping (which zone, which tx). ---
CREATE TABLE IF NOT EXISTS capabilities (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id  uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  zone         bigint NOT NULL,      -- matches the on-chain token id
  grant_tx     text,                 -- AccessControlNFT.grantAccess tx hash
  revoked_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- --- Access logs: physical-access events. NEVER on-chain (GDPR, §10). ---
CREATE TABLE IF NOT EXISTS access_logs (
  id           bigserial PRIMARY KEY,
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id  uuid REFERENCES employees(id) ON DELETE SET NULL,
  zone         bigint NOT NULL,
  granted      boolean NOT NULL,
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

-- --- Revocation outbox: on-chain revokes that FAILED during GDPR erasure, kept for
-- durable retry (audit finding #2). PII is already deleted by then; this row holds only
-- the pseudonymous wallet + zone, never identity. ---
CREATE TABLE IF NOT EXISTS revocation_outbox (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  wallet       text NOT NULL,
  zone         bigint NOT NULL,
  reason       text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  retried_at   timestamptz
);

-- =============================================================================
-- Row-Level Security: each request runs with app.current_tenant set; a tenant
-- can only see/modify its own rows. FORCE so even the table owner is bound.
-- =============================================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['employees','capabilities','access_logs','revocation_outbox'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($f$
      CREATE POLICY tenant_isolation ON %I
        USING (tenant_id = current_setting('app.current_tenant', true)::uuid)
        WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid)
    $f$, t);
  END LOOP;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON employees, capabilities, access_logs, revocation_outbox TO gemba_app;
GRANT SELECT, INSERT ON tenants TO gemba_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gemba_app;

-- NOTE (GDPR right to erasure): deleting an employee cascades to its capabilities
-- and nulls its access_logs.employee_id, removing all PII and the identity bridge.
-- The on-chain capability token remains but is now unlinked from any identity —
-- anonymous and de-identified. To also revoke on-chain access, the service calls
-- AccessControlNFT.revokeAccess(wallet, zone) before/at erasure (see src/gdpr.js).
