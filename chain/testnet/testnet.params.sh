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

# --- allocation (total = 100,000,000 test GMB, mirroring mainnet §4.1 shape) ---
# circulation = 5 validators x 2,000,000; drip faucet 20M; reserves as on mainnet
# but trimmed to fit the 20M drip account. Sums to 100M.
TN_VAL_EACH="2000000"           # per genesis validator (self-bonds 1M of it)
TN_ALLOC_REWARD_RESERVE="20000000"   # rewardstreamer module account (20M)
TN_ALLOC_FAUCET_MODULE="20000000"    # faucet module account (40%-fee intake)
TN_ALLOC_FOUNDATION="10000000"
TN_ALLOC_DAO="10000000"
TN_ALLOC_LIQUIDITY="5000000"
TN_ALLOC_FOUNDER="5000000"
# 5*2,000,000 + 20,000,000(drip) + 20,000,000 + 20,000,000 + 10,000,000
#   + 10,000,000 + 5,000,000 + 5,000,000 = 100,000,000 ✓

# --- testnet conveniences (shorter than mainnet for faster iteration) ---
TN_UNBONDING_TIME="259200s"     # 3 days (mainnet would be 14-21d, §5.5)
