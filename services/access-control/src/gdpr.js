// GDPR right-to-erasure logic (CLAUDE.md §10). Pure / dependency-injected so it is
// unit-test runnable without a live DB or chain.
//
// The split: on-chain capabilities are anonymous (an address holding a zone token);
// the IDENTITY lives only off-chain. Erasing an employee therefore means:
//   1. (optionally) revoke their on-chain capabilities so they lose access, then
//   2. delete the off-chain PII + the identity->NFT bridge + their logs.
// After step 2 the on-chain token (if not revoked) is unlinked from any identity —
// de-identified — satisfying erasure of personal data while the chain stays
// immutable and verifiable.

/**
 * Erase an employee's personal data.
 * @param {object} deps
 * @param {object} deps.db    - object with getEmployeeCapabilities(employeeId) -> [{zone, wallet}], deleteEmployee(employeeId)
 * @param {object} deps.chain - object with revokeAccess(wallet, zone) -> txHash (may be null to skip on-chain revocation)
 * @param {string} employeeId
 * @param {object} [opts]
 * @param {boolean} [opts.revokeOnChain=true] - also revoke on-chain capabilities
 * @returns {Promise<{employeeId, revoked: Array, deleted: boolean}>}
 */
export async function eraseEmployee({ db, chain }, employeeId, opts = {}) {
  const revokeOnChain = opts.revokeOnChain !== false;

  // Capture capabilities BEFORE deletion (we need wallet+zone to revoke afterwards).
  const caps = revokeOnChain && chain ? await db.getEmployeeCapabilities(employeeId) : [];

  // 1. Delete off-chain PII + identity bridge + logs FIRST (schema cascades). This is the
  //    legally-significant erasure (GDPR right to erasure, CLAUDE.md §10) and must NOT be
  //    blocked by chain/RPC availability (audit finding #2). On-chain tokens become
  //    de-identified — verifiable but no longer linked to any person.
  await db.deleteEmployee(employeeId);

  // 2. Best-effort on-chain revocation AFTER erasure. One failure must not abort the
  //    others, and an already-revoked token must not deadlock retries — record per-cap
  //    outcome instead of throwing. Callers run this with no DB transaction held (#1).
  const revoked = [];
  for (const cap of caps) {
    try {
      const txHash = await chain.revokeAccess(cap.wallet, cap.zone);
      revoked.push({ zone: cap.zone, wallet: cap.wallet, txHash, ok: true });
    } catch (err) {
      const reason = String(err.message || err);
      revoked.push({ zone: cap.zone, wallet: cap.wallet, error: reason, ok: false });
      // durably record the still-valid on-chain capability so it can be retried — the
      // PII (and its cascade) is already gone, so the HTTP response is the only other
      // trace; the outbox row holds no PII, just wallet+zone (audit finding #2).
      if (db.recordFailedRevocation) {
        try {
          await db.recordFailedRevocation({ wallet: cap.wallet, zone: cap.zone, reason });
        } catch (_e) {
          /* outbox best-effort; never let it block erasure */
        }
      }
    }
  }

  return { employeeId, revoked, deleted: true };
}
