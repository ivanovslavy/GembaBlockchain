// Revocation-outbox retry worker (audit finding #6). When a GDPR on-chain revoke fails during
// erasure, it is queued in revocation_outbox; this worker drains it later so the on-chain
// capability is eventually revoked. PII is already deleted; the rows hold only wallet + zone.

import { tenantRepo, listTenantIds } from './db.js';

/**
 * Process one tenant's pending revocations. Pure-ish: takes a tenant-scoped repo + chain client,
 * so it is unit-testable. The chain call is made with NO DB transaction held (the repo runs each
 * query in its own short tx), preserving the finding-#1 invariant.
 * @returns {Promise<{ok:number, failed:number, total:number}>}
 */
export async function processOutboxFor(repo, chain, limit = 100) {
  const pending = await repo.listPendingRevocations(limit);
  let ok = 0;
  let failed = 0;
  for (const row of pending) {
    try {
      await chain.revokeAccess(row.wallet, row.zone);
      await repo.markRevocationRetried(row.id);
      ok++;
    } catch {
      failed++; // leave retried_at NULL → picked up again next run (with eventual backoff/alerting)
    }
  }
  return { ok, failed, total: pending.length };
}

/** Drain every tenant's outbox once. */
export async function processOutbox(pool, chain, { limit = 100 } = {}) {
  const tenantIds = await listTenantIds(pool);
  let ok = 0;
  let failed = 0;
  for (const tid of tenantIds) {
    const r = await processOutboxFor(tenantRepo(pool, tid), chain, limit);
    ok += r.ok;
    failed += r.failed;
  }
  return { ok, failed };
}

/** Start a periodic outbox drain. Returns the timer (unref'd so it never blocks shutdown). */
export function startOutboxWorker(pool, chain, intervalMs = 60_000) {
  const timer = setInterval(() => {
    processOutbox(pool, chain).catch((e) => console.error('[outbox worker]', e.message));
  }, intervalMs);
  timer.unref?.();
  return timer;
}
