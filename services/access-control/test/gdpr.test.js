import { test } from 'node:test';
import assert from 'node:assert/strict';
import { eraseEmployee } from '../src/gdpr.js';

test('eraseEmployee deletes off-chain PII FIRST, then best-effort revokes on-chain', async () => {
  const order = [];
  const db = {
    getEmployeeCapabilities: async () => [
      { zone: 7, wallet: '0xabc' },
      { zone: 9, wallet: '0xabc' },
    ],
    deleteEmployee: async (id) => order.push(`delete:${id}`),
  };
  const chain = {
    revokeAccess: async (wallet, zone) => {
      order.push(`revoke:${zone}`);
      return `0xtx${zone}`;
    },
  };

  const res = await eraseEmployee({ db, chain }, 'emp-1');

  assert.equal(res.deleted, true);
  assert.equal(res.revoked.length, 2);
  assert.equal(res.revoked[0].txHash, '0xtx7');
  assert.equal(res.revoked[0].ok, true);
  // PII deletion happens FIRST (erasure must not depend on the chain — finding #2)
  assert.deepEqual(order, ['delete:emp-1', 'revoke:7', 'revoke:9']);
});

test('eraseEmployee still deletes PII when an on-chain revoke fails (finding #2)', async () => {
  let deleted = false;
  const db = {
    getEmployeeCapabilities: async () => [
      { zone: 7, wallet: '0xabc' },
      { zone: 9, wallet: '0xabc' },
    ],
    deleteEmployee: async () => {
      deleted = true;
    },
  };
  const chain = {
    revokeAccess: async (_wallet, zone) => {
      if (zone === 7) throw new Error('RPC down'); // transient chain failure
      return `0xtx${zone}`;
    },
  };

  const res = await eraseEmployee({ db, chain }, 'emp-3');

  assert.equal(deleted, true); // PII erased despite the chain failure
  assert.equal(res.deleted, true);
  assert.equal(res.revoked.length, 2);
  assert.equal(res.revoked[0].ok, false); // zone 7 failed, recorded not thrown
  assert.equal(res.revoked[1].ok, true); // zone 9 still attempted + succeeded
});

test('eraseEmployee can skip on-chain revocation (off-chain erasure only)', async () => {
  let deleted = false;
  const db = {
    getEmployeeCapabilities: async () => {
      throw new Error('must not query capabilities when skipping on-chain');
    },
    deleteEmployee: async () => {
      deleted = true;
    },
  };
  const res = await eraseEmployee({ db, chain: null }, 'emp-2', { revokeOnChain: false });
  assert.equal(deleted, true);
  assert.equal(res.revoked.length, 0);
});
