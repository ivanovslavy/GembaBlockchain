import { test } from 'node:test';
import assert from 'node:assert/strict';
import { eraseEmployee } from '../src/gdpr.js';

test('eraseEmployee revokes on-chain capabilities then deletes off-chain PII', async () => {
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
  // off-chain delete happens AFTER on-chain revocations
  assert.deepEqual(order, ['revoke:7', 'revoke:9', 'delete:emp-1']);
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
