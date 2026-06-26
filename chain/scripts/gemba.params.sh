# =============================================================================
# gemba.params.sh — GembaBlockchain genesis economic anchors (Phase 1, local devnet)
# =============================================================================
# These are NOT arbitrary devnet values. They are the genesis-baked economics
# from CLAUDE.md and docs/risks.md. They get frozen into genesis, so they must
# be right from the first block. Each block cites the spec section / ADR it
# enforces. Change CLAUDE.md first, then this file (CLAUDE.md §0.5).
# -----------------------------------------------------------------------------

# --- Identity (CLAUDE.md §1) ---
COSMOS_CHAIN_ID="gemba-1"        # Cosmos chain-id (string)
EVM_CHAIN_ID="821206"            # EIP-155 EVM chainId — SEPARATE from cosmos id, set in app.toml
KEYALGO="eth_secp256k1"          # eth_secp256k1 / SLIP-0044 coin type 60 -> 0x addresses, MetaMask
KEYRING="test"                   # DEVNET ONLY. Never 'test' on a public node (CLAUDE.md §14)

# --- Native coin GMB (18 decimals, EVM gas token) ---
# Base denom is atto-GMB ("agmb", 1e-18 GMB), display is "GMB", like wei/ETH.
# 18 decimals => extended denom == base denom (see x/vm/keeper/coin_info.go).
BASE_DENOM="agmb"                # smallest unit, what the EVM/bank use internally
DISPLAY_DENOM="GMB"              # human display, exponent 18
DECIMALS="18"

# --- Block time: target ~3s (regenesis decision 2026-06-26; ~2x faster than the old ~5.5s) ---
# CometBFT block time = timeout_commit + the real consensus round-trip between validators. With
# the prior 2s commit blocks landed ~5.5s (geo + the NAT'd node's latency dominate). Dropping the
# commit to 1s targets ~3s blocks; the floor below that is the inter-validator RTT, not config.
TIMEOUT_COMMIT="1s"

# --- Active validator set cap (CLAUDE.md §5.2: permissionless + ranked, O(n^2)) ---
MAX_VALIDATORS="150"

# =============================================================================
# SECURITY-BUDGET ANCHORS  (docs/risks.md ADR-008 / ADR-008a)
# =============================================================================
# Zero inflation (CLAUDE.md §3.1, §4.2): supply is minted ONCE at genesis and
# never again. We disable the mint module's inflation entirely.
MINT_INFLATION="0.000000000000000000"
MINT_INFLATION_MAX="0.000000000000000000"
MINT_INFLATION_MIN="0.000000000000000000"
MINT_INFLATION_RATE_CHANGE="0.000000000000000000"

# Fees are "low but non-zero, scaling with usage" (CLAUDE.md §1, §16.8; ADR-008a):
#   - per-tx cost stays cheap (a 21k-gas transfer ~= 0.000021 GMB at 1 gwei),
#   - but the gas price has a NON-ZERO floor so aggregate fees = real security
#     budget in real value (NOT zero — upstream evmd defaults min_gas_price=0,
#     which we deliberately override), and
#   - EIP-1559 base fee rises with block fullness => security budget scales with
#     usage (mechanism (a) of ADR-008).
# Units are agmb-per-gas (like wei-per-gas). 1 gwei-equivalent = 1e9 agmb.
# Regenesis decision 2026-06-26: fee floor raised 1 -> 5 gwei (more recirculation 60/40 to
# validators/faucet + larger security budget; still negligible per tx — a 21k-gas transfer ~=
# 0.0001 GMB ~= 0.01 cent at 1 GMB = 1 EUR).
BASE_FEE="5000000000.000000000000000000"        # 5 gwei starting base fee
MIN_GAS_PRICE="5000000000.000000000000000000"    # 5 gwei FLOOR (ADR-008a, non-zero)
MIN_GAS_PRICES_NODE="5000000000agmb"             # validator mempool floor (app.toml / --minimum-gas-prices)
# EIP-1559 dynamics (defaults): base fee moves +-1/8 (12.5%) per block toward a
# 1/elasticity full target => "scaling with usage".
ELASTICITY_MULTIPLIER="2"
BASE_FEE_CHANGE_DENOMINATOR="8"

# NOTE: the post-year-10 TAIL REWARD (ADR-008 mechanism (b), recirculation-funded,
# never minted) is intentionally NOT in this devnet — it is a custom Go module
# scheduled for a later phase. Scope is reserved in /chain (see chain/README.md);
# do not add minting to fake it.

# =============================================================================
# GENESIS ALLOCATION — fixed total supply N = 100,000,000 GMB (CLAUDE.md §4.1)
# =============================================================================
# Whole-GMB amounts; the scripts multiply by 1e18 to get agmb. Sum MUST be 100M.
# Only the circulation pool is a VOTING base once staked; every reserve bucket is
# a plain (later: contract) account that holds supply but is NOT staked, so it
# does NOT vote — invariant CLAUDE.md §3.4 / §7.
ALLOC_FAUCET="30000000"          # 30% public/municipal reserve (the faucet)
ALLOC_VAL_RESERVE="20000000"     # 20% validator rewards reserve (~10 yrs, ADR-008)
ALLOC_FOUNDATION="15000000"      # 15% foundation
ALLOC_DAO="10000000"             # 10% DAO reserve
ALLOC_LIQUIDITY="10000000"       # 10% liquidity reserve
ALLOC_FOUNDER="5000000"          #  5% founder / operations (non-voting, CLAUDE.md §3.5)
ALLOC_CIRCULATION="10000000"     # 10% client/circulation pool — the VOTING base

# How the 10% circulation pool is used on devnet:
#  - each genesis validator self-bonds SELF_BOND_GMB out of circulation (so
#    consensus power comes from circulation, never from a reserve), and
#  - the remainder stays liquid in validator + client accounts.
SELF_BOND_GMB="10000"            # 10,000 GMB self-bonded per genesis validator (regenesis §11:
                                 # the max entry self-bond; was 1,000,000 pre-regenesis but the
                                 # valgate max-self-bond cap now rejects anything above 10,000)
MIN_SELF_BOND_GMB="1000"   # x/valgate floor (gentx --min-self-delegation must be >= this)
