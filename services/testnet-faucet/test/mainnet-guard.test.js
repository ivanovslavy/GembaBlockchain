// The MAINNET start guard (owner decision 2026-07-17): the public faucet runs on mainnet
// ONLY in contract mode (FAUCET_CONTRACT -> GembaDripFaucet). Raw-send mode holds a hot key
// with no on-chain cooldown — starting it against chainId 821206 must be refused.

process.env.NODE_ENV = 'test';
process.env.FAUCET_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'; // throwaway test key (anvil #1)

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

const { assertNotRawModeOnMainnet } = await import('../src/server.js');

// tiny JSON-RPC stub answering eth_chainId with a fixed value
function rpcStub(chainIdHex) {
  const srv = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const { id } = JSON.parse(body || '{}');
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ jsonrpc: '2.0', id, result: chainIdHex }));
    });
  });
  return new Promise((resolve) => srv.listen(0, () => resolve({ url: `http://127.0.0.1:${srv.address().port}`, close: () => srv.close() })));
}

test('raw-send mode against MAINNET (821206) is refused', async () => {
  const rpc = await rpcStub('0xc87d6'); // 821206
  try {
    await assert.rejects(
      assertNotRawModeOnMainnet({ rpcUrl: rpc.url, faucetContract: undefined }),
      /refusing to start.*MAINNET/i
    );
  } finally {
    rpc.close();
  }
});

test('raw-send mode against the testnet (821207) is allowed', async () => {
  const rpc = await rpcStub('0xc87d7'); // 821207
  try {
    await assertNotRawModeOnMainnet({ rpcUrl: rpc.url, faucetContract: undefined });
  } finally {
    rpc.close();
  }
});

test('contract mode is allowed everywhere (no RPC probe needed)', async () => {
  await assertNotRawModeOnMainnet({ rpcUrl: 'http://127.0.0.1:1', faucetContract: '0x0D16a7a490eB2f4766480424E28EE0187d5c74AB' });
});
