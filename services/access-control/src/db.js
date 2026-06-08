// PostgreSQL access with Row-Level Security. The app connects as the non-superuser
// `gemba_app` role; every request runs inside a transaction that sets
// `app.current_tenant`, so the RLS policies (db/schema.sql) scope all rows to the
// caller's institution. This is what guards the identity->NFT bridge (CLAUDE.md §10).

import pg from 'pg';

const { Pool } = pg;

export function createPool(connectionString) {
  return new Pool({ connectionString });
}

/**
 * Refuse to run on a DB role that bypasses RLS (audit finding #3). A PostgreSQL superuser
 * (or a role with BYPASSRLS) ignores RLS entirely, silently collapsing all tenant isolation.
 * Call this at startup and abort if the connected role is unsafe — fail loud, never silent.
 */
export async function assertSafeDbRole(pool) {
  const { rows } = await pool.query(
    "SELECT current_setting('is_superuser') = 'on' AS is_superuser, " +
      'COALESCE((SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user), false) AS bypassrls'
  );
  const r = rows[0];
  if (r.is_superuser || r.bypassrls) {
    throw new Error(
      'refusing to start: DB role is a superuser or has BYPASSRLS — RLS tenant isolation would be bypassed (set DATABASE_URL to the non-privileged gemba_app role)'
    );
  }
}

/**
 * Run `fn(client)` in a transaction with `app.current_tenant` set, so RLS applies.
 * SET LOCAL is transaction-scoped; the tenant id is bound as a parameter.
 */
export async function withTenant(pool, tenantId, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.current_tenant', $1, true)", [tenantId]);
    const result = await fn(repo(client, tenantId));
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Tenant-scoped repository where EACH method runs in its OWN short RLS transaction.
 * Use this in request handlers so an on-chain call (which awaits a block, ~seconds)
 * is never made while a pooled DB connection is held open inside a transaction
 * (audit finding #1 — pool-exhaustion DoS + on/off-chain divergence). Read in one
 * short tx, do the chain call with no tx held, then write in another short tx.
 */
export function tenantRepo(pool, tenantId) {
  const run = (fn) => withTenant(pool, tenantId, fn);
  return {
    createEmployee: (a) => run((db) => db.createEmployee(a)),
    listEmployees: () => run((db) => db.listEmployees()),
    getEmployeeWallet: (id) => run((db) => db.getEmployeeWallet(id)),
    createCapability: (a) => run((db) => db.createCapability(a)),
    getEmployeeCapabilities: (id) => run((db) => db.getEmployeeCapabilities(id)),
    logAccess: (a) => run((db) => db.logAccess(a)),
    deleteEmployee: (id) => run((db) => db.deleteEmployee(id)),
    recordFailedRevocation: (a) => run((db) => db.recordFailedRevocation(a)),
    listPendingRevocations: (limit) => run((db) => db.listPendingRevocations(limit)),
    markRevocationRetried: (id) => run((db) => db.markRevocationRetried(id)),
  };
}

/** Tenant-scoped repository bound to a client inside a withTenant transaction. */
export function repo(client, tenantId) {
  return {
    async createEmployee({ fullName, email, wallet }) {
      const { rows } = await client.query(
        `INSERT INTO employees (tenant_id, full_name, email, wallet)
         VALUES ($1, $2, $3, $4) RETURNING id, wallet`,
        [tenantId, fullName, email, wallet]
      );
      return rows[0];
    },

    // RLS-scoped: returns only the calling tenant's employees.
    async listEmployees() {
      const { rows } = await client.query(`SELECT id, full_name, wallet FROM employees ORDER BY created_at`);
      return rows;
    },

    async getEmployeeWallet(employeeId) {
      const { rows } = await client.query(`SELECT wallet FROM employees WHERE id = $1`, [employeeId]);
      return rows[0]?.wallet ?? null;
    },

    async createCapability({ employeeId, zone, grantTx }) {
      const { rows } = await client.query(
        `INSERT INTO capabilities (tenant_id, employee_id, zone, grant_tx)
         VALUES ($1, $2, $3, $4) RETURNING id`,
        [tenantId, employeeId, zone, grantTx]
      );
      return rows[0];
    },

    async getEmployeeCapabilities(employeeId) {
      const { rows } = await client.query(
        `SELECT c.zone, e.wallet
         FROM capabilities c JOIN employees e ON e.id = c.employee_id
         WHERE c.employee_id = $1 AND c.revoked_at IS NULL`,
        [employeeId]
      );
      return rows;
    },

    async logAccess({ employeeId, zone, granted }) {
      await client.query(
        `INSERT INTO access_logs (tenant_id, employee_id, zone, granted) VALUES ($1, $2, $3, $4)`,
        [tenantId, employeeId, zone, granted]
      );
    },

    // GDPR erasure: cascades remove capabilities and null log references.
    async deleteEmployee(employeeId) {
      await client.query(`DELETE FROM employees WHERE id = $1`, [employeeId]);
    },

    // Durable record of an on-chain revoke that failed during erasure (audit finding #2),
    // so it can be retried later. Holds no PII — only wallet + zone.
    async recordFailedRevocation({ wallet, zone, reason }) {
      await client.query(
        `INSERT INTO revocation_outbox (tenant_id, wallet, zone, reason) VALUES ($1, $2, $3, $4)`,
        [tenantId, wallet, zone, reason ?? null]
      );
    },

    // Outbox retry (audit finding #6): list not-yet-retried revocations, and mark one done.
    async listPendingRevocations(limit = 100) {
      const { rows } = await client.query(
        `SELECT id, wallet, zone FROM revocation_outbox WHERE retried_at IS NULL ORDER BY created_at LIMIT $1`,
        [limit]
      );
      return rows;
    },
    async markRevocationRetried(id) {
      await client.query(`UPDATE revocation_outbox SET retried_at = now() WHERE id = $1`, [id]);
    },
  };
}

/** All tenant ids (the tenants table is not RLS-scoped); used by the outbox retry worker. */
export async function listTenantIds(pool) {
  const { rows } = await pool.query('SELECT id FROM tenants');
  return rows.map((r) => r.id);
}
