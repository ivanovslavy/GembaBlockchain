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
  const revoked = [];

  if (revokeOnChain && chain) {
    const caps = await db.getEmployeeCapabilities(employeeId);
    for (const cap of caps) {
      // best-effort on-chain revocation; record the result, never swallow silently
      const txHash = await chain.revokeAccess(cap.wallet, cap.zone);
      revoked.push({ zone: cap.zone, wallet: cap.wallet, txHash });
    }
  }

  // Delete off-chain PII + identity bridge + logs (schema cascades).
  await db.deleteEmployee(employeeId);

  return { employeeId, revoked, deleted: true };
}
