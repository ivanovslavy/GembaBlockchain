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
  };
}
