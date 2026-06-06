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
TN_VALIDATORS=5
TN_SELF_BOND_GMB="1000000"      # 1,000,000 test GMB self-bonded per validator

# --- testnet drip faucet account (the faucet SERVICE controls this key) ---
# DEVNET/TESTNET-ONLY well-known key — valueless tokens. dev2 from cosmos/evm.
TN_FAUCET_MNEMONIC="***REMOVED-ROTATED-FAUCET-MNEMONIC***"
TN_FAUCET_ADDR_0X="0x40a0cb1C63e026A81B55EE1308586E21eec1eFa9"  # dev2
TN_FAUCET_ALLOC="20000000"      # 20,000,000 test GMB to drip to testers

# --- allocation: EXACT mainnet §4.1 %s of 100M (corrected 2026-06-06, re-genesis path A) ---
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
