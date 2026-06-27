#!/usr/bin/env bash
# security/config.sh — single source of truth for the security harness AFTER the
# 2026-06-27 regenesis. Sourced by every e2e probe so addresses/RPC live in one place.
# Public, read-only data only (no keys). Chain gemba-testnet-1 / EVM 821207.

# --- endpoints (public; each rpcN = one Contabo validator behind Cloudflare) ---
export SEC_CHAIN_ID_DEC=821207
export SEC_CHAIN_ID_HEX=0xc87d7
export SEC_RPC1=https://rpc1.gembascan.io
export SEC_RPC2=https://rpc2.gembascan.io
export SEC_RPC3=https://rpc3.gembascan.io
export SEC_RPC_LOCAL=http://localhost:8565          # local archive (dev box), if up
export SEC_EXPLORER=https://testnet.gembascan.io     # gembascan (Blockscout)
export SEC_COMETBFT=http://13.140.139.82:26657       # validator CometBFT RPC (may be firewalled)

# pick a working EVM RPC (prefer local archive, fall back to public rpc1)
sec_rpc() {
  if curl -s --max-time 4 -X POST "$SEC_RPC_LOCAL" -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | grep -q "$SEC_CHAIN_ID_HEX"; then
    echo "$SEC_RPC_LOCAL"; else echo "$SEC_RPC1"; fi
}

# --- PROTOCOL contracts (CREATE2, 2026-06-27) ---
export C_TIMELOCK=0xa75aC1AF72D54e34c5646534F985Be7a172C37C1
export C_VOTES=0x0056ab3c91FF5ba8eCdBA8c7C453fd9F424F7F39
export C_GOVERNOR=0xCCd9f78047E1BB8Bec419490E80409bfBf3B7b72
export C_EMERGENCYPAUSE=0x372462Fc8e28c558E2A1bcE6b9CF56a47c71DeA0
export C_FAUCET=0x9406B634Eae1856d13251245d7D472D9b6594F56
export C_FOUNDATION=0x353CC67C2000fC9b142C0aa505a2e45DA693CDe0
export C_DAO=0x68093A1C9682df9D1C59586b2Cfc04ed132e7eE5
export C_CONTINGENCY=0xCBbf84966335e0846cffB52d8624a9aeF58227b4
export C_DRIPFAUCET=0x0D16a7a490eB2f4766480424E28EE0187d5c74AB
export C_ONRAMP=0xC35E5F9AD571499785060aa63e3Eb492DbB3Fd17
export C_TICKETING=0xDe541f5E11af36cAE643D04F2e49fA54Cf14B6ce
export C_PERKS=0x0c4ab65FC5A295995A0ef50714aA4e2f33b6ada6
export C_FORWARDER=0x5c7A951ed32c3ce77f4b6e6585018eB5b32C426E
export C_CHECKIN=0xbD57C7CD844ad0aC23a4e1D6B9F016E3FE89bE19
export C_ACCESSNFT=0xE2DCB80ee598Dd0eb0dda8179A51c02b7C266a98

# --- dApp contracts (redeployed 2026-06-27) ---
export D_GEMBAWIN_FACTORY=0xb77b4c87bc1B9237e5B743a5D33B107c502C5FDC
export D_GEMBAWIN_FAUCET=0x0147581e2351dD182edD651DFEfD955CB353f8aA
export D_GEMBATICKET_REGISTRY=0x32977E6391e7C25BF0Ddc2a5f4c9A311e5bA1d02
export D_EDUCHAIN_GAMETOKEN=0x385335b67d8c6C3cb7114D4a907Ca6017391279B
export D_EDUCHAIN_FAUCET=0x6056Cb44e9C6A429D45BBaC254FbD2D8CDa40D47
export D_ESCROW_FACTORY=0xf2dc67274CCd82bcFa3e446BcD55fB1889866e26
export D_GEMBAPASS=0x1B72b95588B75925B59715d582504C9D42594899

# --- expected invariants ---
export EXP_TOTAL_SUPPLY_GMB=100000000
export EXP_VALIDATORS=4
export EXP_FEE_FLOOR_GWEI=5

# dApp public URLs (for liveness checks)
export DAPP_URLS="educhain.gembait.com escrow.gembait.com win.gembait.com gembaticket.com gembapass.com"
