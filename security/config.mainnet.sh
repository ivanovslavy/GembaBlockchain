#!/usr/bin/env bash
# security/config.mainnet.sh — harness config for MAINNET gemba-1 / EVM 821206.
# PREPARED 2026-07-18 (pre-launch): endpoint constants are final (gmb1/2/3 map,
# owner 2026-07-17); CONTRACT addresses are ceremony/deploy-day values — the
# governance set is CREATE2, so precompute them via `forge script` simulation and
# fill BEFORE launch day. Use by pointing the harness at this file:
#   SEC_CONFIG=security/config.mainnet.sh ./security/e2e/run-e2e.sh   (post-launch)
# Public, read-only data only (no keys).

# --- endpoints (gmb1 -> .82, gmb2 -> .83, gmb3 -> .84, behind Cloudflare) ---
export SEC_CHAIN_ID_DEC=821206
export SEC_CHAIN_ID_HEX=0xc87d6
export SEC_RPC1=https://gmb1.gembascan.io
export SEC_RPC2=https://gmb2.gembascan.io
export SEC_RPC3=https://gmb3.gembascan.io
export SEC_RPC_LOCAL=http://localhost:8565          # local archive (dev box), if up
export SEC_EXPLORER=https://gembascan.io             # gembascan (Blockscout)
export SEC_COMETBFT=http://13.140.139.82:26657       # validator CometBFT RPC (firewalled)

# pick a working EVM RPC (prefer local archive, fall back to public gmb1)
sec_rpc() {
  if curl -s --max-time 4 -X POST "$SEC_RPC_LOCAL" -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | grep -q "$SEC_CHAIN_ID_HEX"; then
    echo "$SEC_RPC_LOCAL"; else echo "$SEC_RPC1"; fi
}

# --- PROTOCOL contracts — FILL at ceremony (CREATE2: precompute via forge simulation) ---
export C_TIMELOCK=
export C_VOTES=
export C_GOVERNOR=
export C_EMERGENCYPAUSE=
export C_FAUCET=          # PublicReserve proxy
export C_FOUNDATION=
export C_DAO=
export C_CONTINGENCY=
export C_DRIPFAUCET=
export C_TICKETING=
export C_PERKS=
export C_FORWARDER=
export C_CHECKIN=
export C_ACCESSNFT=
# C_ONRAMP intentionally ABSENT: GembaOnRamp was removed from the codebase
# 2026-07-17 — live-invariants.sh then asserts "no public sale by construction".
export C_DISPENSER=       # GembaPayDispenser (new mainnet deploy — NOT the testnet 0x0EB2)
export C_COLLECTOR=       # GmbCollector

# --- dApp contracts (ecosystem repos; fill as each dApp goes live on mainnet) ---
export D_GEMBAWIN_FACTORY=
export D_GEMBAWIN_FAUCET=
export D_GEMBATICKET_REGISTRY=
export D_EDUCHAIN_GAMETOKEN=
export D_EDUCHAIN_FAUCET=
export D_ESCROW_FACTORY=
export D_GEMBAPASS=
