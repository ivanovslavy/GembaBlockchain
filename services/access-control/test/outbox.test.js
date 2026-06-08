import { test } from 'node:test';
import assert from 'node:assert/strict';
import { processOutboxFor } from '../src/outbox.js';

test('processOutboxFor revokes pending and marks them retried', async () => {
  const retried = [];
  const repo = {
    listPendingRevocations: async () => [
      { id: 'a', wallet: '0x1', zone: 7 },
      { id: 'b', wallet: '0x2', zone: 9 },
    ],
    markRevocationRetried: async (id) => retried.push(id),
  };
  const chain = { revokeAccess: async () => '0xtx' };
  const r = await processOutboxFor(repo, chain);
  assert.equal(r.ok, 2);
  assert.equal(r.failed, 0);
  assert.deepEqual(retried, ['a', 'b']);
});

test('processOutboxFor leaves a row unretried when the revoke fails (retried next run)', async () => {
  const retried = [];
  const repo = {
    listPendingRevocations: async () => [
      { id: 'a', wallet: '0x1', zone: 7 },
      { id: 'b', wallet: '0x2', zone: 9 },
    ],
    markRevocationRetried: async (id) => retried.push(id),
  };
  const chain = {
    revokeAccess: async (_w, zone) => {
      if (zone === 7) throw new Error('RPC down');
      return '0xtx';
    },
  };
  const r = await processOutboxFor(repo, chain);
  assert.equal(r.ok, 1);
  assert.equal(r.failed, 1);
  assert.deepEqual(retried, ['b']); // 'a' stays pending for the next run
});
