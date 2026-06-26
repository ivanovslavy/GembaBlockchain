// End-to-end test of the faucet's OFF-CHAIN guard flow (the testnet protection): it drives
// the real Express /drip handler + the real CooldownLimiter / global-budget / min-balance
// logic, with a MOCK faucet (no RPC). Proves the per-address cooldown, the per-IP cooldown,
// the balance floor, and the failed-send rollback all behave. (The MAINNET faucet adds the
// on-chain cooldown contract on top — covered by contracts/test/GembaDripFaucet.t.sol.)

process.env.NODE_ENV = 'test';
process.env.FAUCET_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'; // throwaway test key (anvil #1)

import test from 'node:test';
import assert from 'node:assert/strict';
// Dynamic import AFTER setting env: static ESM imports are hoisted, so server.js (which reads
// FAUCET_KEY at module load) must be imported here, not at the top, or it sees an unset key.
const { createApp } = await import('../src/server.js');
const { CooldownLimiter } = await import('../src/ratelimit.js');

const A = '0x1111111111111111111111111111111111111111';
const B = '0x2222222222222222222222222222222222222222';
const C = '0x3333333333333333333333333333333333333333';
const D = '0x4444444444444444444444444444444444444444';
const FLOOR = 1000n * 10n ** 18n;

function mockFaucet() {
  return {
    address: '0xfaucet0000000000000000000000000000000000',
    _bal: 10_000n * 10n ** 18n,
    _fail: false,
    async balance() { return this._bal; },
    async drip(to) { if (this._fail) throw new Error('send failed'); return '0xhash_' + to.slice(2, 8); },
  };
}

async function startApp(deps) {
  const app = createApp(deps);
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;
  return { server, port };
}

// POST /drip with a chosen client IP (trust proxy = 1 => req.ip is the X-Forwarded-For value).
async function drip(port, address, ip) {
  const res = await fetch(`http://127.0.0.1:${port}/drip`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-forwarded-for': ip },
    body: JSON.stringify({ address }),
  });
  return { status: res.status, body: await res.json() };
}

test('off-chain faucet guard flow', async (t) => {
  const faucet = mockFaucet();
  const { server, port } = await startApp({
    faucet,
    byAddress: new CooldownLimiter(60_000),
    byIp: new CooldownLimiter(60_000),
  });
  t.after(() => server.close());

  await t.test('first drip succeeds', async () => {
    const r = await drip(port, A, '1.1.1.1');
    assert.equal(r.status, 200);
    assert.equal(r.body.ok, true);
  });

  await t.test('same address again -> address cooldown', async () => {
    const r = await drip(port, A, '1.1.1.1');
    assert.equal(r.status, 429);
    assert.match(r.body.error, /address on cooldown/);
  });

  await t.test('fresh address but same IP -> ip cooldown', async () => {
    const r = await drip(port, B, '1.1.1.1');
    assert.equal(r.status, 429);
    assert.match(r.body.error, /ip on cooldown/);
  });

  await t.test('fresh address + fresh IP -> succeeds', async () => {
    const r = await drip(port, B, '2.2.2.2');
    assert.equal(r.status, 200);
    assert.equal(r.body.ok, true);
  });

  await t.test('below balance floor -> 503 (circuit breaker)', async () => {
    faucet._bal = 0n;
    const r = await drip(port, C, '3.3.3.3');
    assert.equal(r.status, 503);
    faucet._bal = 10_000n * 10n ** 18n;
  });

  await t.test('failed send rolls back the cooldown (retry works)', async () => {
    faucet._fail = true;
    const r1 = await drip(port, D, '4.4.4.4');
    assert.equal(r1.status, 500); // opaque error
    faucet._fail = false;
    const r2 = await drip(port, D, '4.4.4.4'); // not stuck on cooldown — rollback worked
    assert.equal(r2.status, 200);
  });

  await t.test('invalid address -> 400', async () => {
    const r = await drip(port, 'not-an-address', '9.9.9.9');
    assert.equal(r.status, 400);
  });
});

void FLOOR;
