# /explorer — Blockscout ("GembaScan")

Self-hosted **Blockscout** (open-source Etherscan/Polygonscan equivalent) via Docker
for the **EVM side** of GembaBlockchain. Provides an Etherscan-compatible API + REST
v2 + GraphQL + WebSocket, Solidity contract verification, and self-issued API keys
(self-hosted ⇒ we control rate limits).

Optionally a **Cosmos-side explorer** (e.g. ping.pub) for staking / governance /
validator views, since those live in Cosmos modules, not the EVM.

**Never commit** DB volumes or API keys (`.gitignore` covers `blockscout-db-data/`).

## Phase

**Phase 7** — stand up the chain + contracts first. Phase 0 placeholder.
