// Entry point. Reads config from the environment (secrets in .env, never committed
// — CLAUDE.md §3) and starts the access-control API.

import { createPool, assertSafeDbRole } from './db.js';
import { createChainClient } from './chain.js';
import { createApp } from './app.js';
import { parseApiKeys } from './auth.js';

const pool = createPool(process.env.DATABASE_URL);
const chain = createChainClient({
  rpcUrl: process.env.EVM_JSONRPC_HTTP || 'http://localhost:8545',
  issuerKey: process.env.ACCESS_ISSUER_PK, // ISSUER_ROLE key — secret
  contractAddress: process.env.ACCESS_CONTROL_NFT_ADDRESS,
});

// API key -> tenant map (secret; never committed). Fail fast if none configured.
const apiKeys = parseApiKeys(process.env.ACCESS_API_KEYS);

const port = process.env.ACCESS_API_PORT || 3001;

(async () => {
  await assertSafeDbRole(pool); // refuse to start on a superuser/BYPASSRLS role (finding #3)
  if (apiKeys.size === 0) {
    throw new Error('refusing to start: ACCESS_API_KEYS is empty — set per-institution API keys (finding #1)');
  }
  createApp({ pool, chain, apiKeys }).listen(port, () => {
    console.log(`access-control API listening on :${port}`);
  });
})().catch((err) => {
  console.error('startup failed:', err.message);
  process.exit(1);
});
