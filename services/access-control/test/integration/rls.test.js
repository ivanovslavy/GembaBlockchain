// RLS integration test — the security centerpiece (CLAUDE.md §10): prove that one
// institution (tenant) can NEVER read another's identity rows. Requires a running
// PostgreSQL with db/schema.sql loaded; DATABASE_URL must connect as the
// non-superuser `gemba_app` role (so RLS is enforced). Skipped if DATABASE_URL is
// unset. See docker-compose.yml + README.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { createPool, withTenant } from '../../src/db.js';

const url = process.env.DATABASE_URL;
const A_WALLET = '0x' + 'a'.repeat(40);
const B_WALLET = '0x' + 'b'.repeat(40);

test('RLS isolates tenants — A cannot see B\'s employees', { skip: !url && 'set DATABASE_URL to run' }, async () => {
  const pool = createPool(url);
  try {
    // gemba_app may INSERT tenants (not tenant-scoped).
    const base = await pool.connect();
    const { rows: [a] } = await base.query("INSERT INTO tenants(name) VALUES('Inst A') RETURNING id");
    const { rows: [b] } = await base.query("INSERT INTO tenants(name) VALUES('Inst B') RETURNING id");
    base.release();

    await withTenant(pool, a.id, (db) => db.createEmployee({ fullName: 'Alice', email: null, wallet: A_WALLET }));
    await withTenant(pool, b.id, (db) => db.createEmployee({ fullName: 'Bob', email: null, wallet: B_WALLET }));

    const seenByA = await withTenant(pool, a.id, (db) => db.listEmployees());
    const seenByB = await withTenant(pool, b.id, (db) => db.listEmployees());

    assert.equal(seenByA.length, 1, 'tenant A sees exactly its own employees');
    assert.equal(seenByA[0].wallet, A_WALLET);
    assert.equal(seenByB.length, 1, 'tenant B sees exactly its own employees');
    assert.equal(seenByB[0].wallet, B_WALLET);
    // The cross-tenant row is invisible — RLS, not application filtering.
    assert.ok(!seenByA.some((e) => e.wallet === B_WALLET), 'A must NOT see B\'s PII');
  } finally {
    await pool.end();
  }
});
