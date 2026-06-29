# =============================================================================
# testnet.params.sh — gemba-testnet-1 parameters (Phase: public testnet).
# A mainnet DRESS REHEARSAL: same economics + custom modules as mainnet, but a
# DISTINCT chain-id / EVM chainId, VALUELESS tokens, and a generous drip faucet.
# Never reuse mainnet keys here. Sourced by the testnet scripts.
# =============================================================================

# --- identity (DISTINCT from mainnet's gemba-1 / 821206 to avoid replay/confusion) ---
TN_COSMOS_CHAIN_ID="gemba-testnet-1"
TN_EVM_CHAIN_ID="821207"

# --- validators: the 5 Hetzner servers (BFT N>=3f+1: 5 tolerate 1 down, §5.3) ---
TN_VALIDATORS=4
TN_SELF_BOND_GMB="1000"          # 1,000 test GMB self-bonded per validator (= min self-bond, faucet-reachable in 10 days)

# --- testnet drip faucet account (the faucet SERVICE controls this key) ---
# The LIVE drip account must use a FRESH operator-generated key kept in the secret store —
# NOT a public well-known mnemonic (audit finding #9). Sourced from env; no committed fallback.
# NOTE (2026-06-27): the separate drip-faucet EOA is RETIRED — the live testnet/mainnet uses the
# founder-owned combo GembaFaucet (docs/faucet.md), and grants draw from the Faucet contract via the
# §4.1 mechanism. These TN_FAUCET_* vars are vestigial; do NOT reuse the old literal address below
# (0x40a0cb1C… was COMPROMISED in pentest P-1 — docs/KEY-INVENTORY.md). Require it from env if ever needed.
TN_FAUCET_MNEMONIC="${TN_FAUCET_MNEMONIC:?set TN_FAUCET_MNEMONIC in your env/secret store (fresh key for the live drip account)}"
TN_FAUCET_ADDR_0X="${TN_FAUCET_ADDR_0X:?set TN_FAUCET_ADDR_0X from your fresh drip key (the old 0x40a0cb1C… is compromised — never reuse)}"
TN_FAUCET_ALLOC="2000000"       # 2,000,000 drip (carved from circulation); the 30M faucet reserve lives in the Faucet contract

# --- allocation: EXACT mainnet §4.1 %s of 100M (corrected 2026-06-06, re-genesis path A) ---
# ⚠️ NOTE (2026-06-29): the MAINNET §4.1 split CHANGED — the 10% circulation pool is FOLDED INTO
# the Contingency reserve (→20M) and the validators + early participants are funded from the
# FOUNDER (5M) / DAO reserve (10M); no standing circulation pool. The numbers below are the
# currently-DEPLOYED testnet (old split, with circulation); the NEXT testnet regenesis should
# adopt the new split to stay a true dress rehearsal — see chain/scripts/gemba.params.sh + CLAUDE.md §4.1.
# Each reserve EOA below holds its exact §4.1 amount and is transferred IN FULL into its
# Solidity reserve contract right after genesis (Timelock custody), so every contract ends
# up holding exactly its %. The testnet DRIP faucet is no longer a separate allocation — it
# draws from the Faucet contract via the real §4.1 grant mechanism (true dress rehearsal).
TN_VAL_EACH="2000000"                # circulation: 5 validators x 2M = 10M (self-bond 1M each)
TN_ALLOC_FAUCET="30000000"           # 30% Public/Municipal Reserve -> Faucet contract
TN_ALLOC_REWARD_RESERVE="20000000"   # 20% validator rewards -> rewardstreamer module
TN_ALLOC_FOUNDATION="15000000"       # 15% -> FoundationTreasury contract
TN_ALLOC_DAO="10000000"              # 10% -> DAOReserve contract
TN_ALLOC_CONTINGENCY="10000000"      # 10% (was liquidity) -> ContingencyReserve contract
TN_ALLOC_FOUNDER="5000000"           # 5%  founder EOA (non-voting)
# 30M + 20M + 15M + 10M + 10M + 5M + 10M(circulation) = 100,000,000 ✓
# NOTE: init-local-testnet.sh must allocate to the faucet/foundation/dao/contingency reserve
# EOAs with these amounts (no faucet MODULE, no separate drip EOA). See
# docs/runbooks/testnet-re-genesis.md.

# --- testnet conveniences (shorter than mainnet for faster iteration) ---
TN_UNBONDING_TIME="259200s"     # 3 days (mainnet would be 14-21d, §5.5)
