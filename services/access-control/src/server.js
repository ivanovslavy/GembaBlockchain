// Entry point. Reads config from the environment (secrets in .env, never committed
// — CLAUDE.md §3) and starts the access-control API.

import { createPool } from './db.js';
import { createChainClient } from './chain.js';
import { createApp } from './app.js';

const pool = createPool(process.env.DATABASE_URL);
const chain = createChainClient({
  rpcUrl: process.env.EVM_JSONRPC_HTTP || 'http://localhost:8545',
  issuerKey: process.env.ACCESS_ISSUER_PK, // ISSUER_ROLE key — secret
  contractAddress: process.env.ACCESS_CONTROL_NFT_ADDRESS,
});

const port = process.env.ACCESS_API_PORT || 3001;
createApp({ pool, chain }).listen(port, () => {
  console.log(`access-control API listening on :${port}`);
});
