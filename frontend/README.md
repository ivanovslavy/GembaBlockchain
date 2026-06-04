# /frontend — React

User-facing web app for GembaBlockchain: wallet connection (MetaMask — standard
`0x...` addresses, chainId **821206**), GMB transfers, staking/delegation views,
governance, access-control NFT management, and (later) tickets/perks.

Talks to the chain via **EVM JSON-RPC** (`8545`/`8546`) and Cosmos REST (`1317`) /
RPC (`26657`), and to `/services` for off-chain features. Endpoints sit behind the
Apache reverse proxy + Let's Encrypt (HTTPS) — see `CLAUDE.md` §11.

## Phase

Incremental, alongside the phases that ship user-facing features. Phase 0 placeholder.
