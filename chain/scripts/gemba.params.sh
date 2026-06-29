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
# Every reserve bucket holds supply but is NOT staked, so it does NOT vote
# (invariant CLAUDE.md §3.4 / §7). MAINNET split (decision 2026-06-29): there is
# NO standing circulation pool — the genesis validators' self-bond and early
# participants are funded from the FOUNDER (5M) or the DAO reserve (10M).
ALLOC_FAUCET="30000000"          # 30% public/municipal reserve -> Faucet contract
ALLOC_VAL_RESERVE="20000000"     # 20% validator rewards reserve -> rewardstreamer module (~10 yrs, ADR-008)
ALLOC_FOUNDATION="15000000"      # 15% -> FoundationTreasury contract
ALLOC_DAO="10000000"             # 10% -> DAOReserve contract (also a source for early-participant grants)
ALLOC_CONTINGENCY="20000000"     # 20% -> ContingencyReserve contract (absorbs the former 10% circulation, 2026-06-29)
ALLOC_FOUNDER="5000000"          #  5% founder/operations EOA (non-voting, §3.5); seeds the validators + early participants
# Sum: 30 + 20 + 15 + 10 + 20 + 5 = 100,000,000 GMB. (No ALLOC_CIRCULATION as of 2026-06-29.)
# Devnet-only alias: the LOCAL devnet scripts (init-single-node/init-multinode, init-gembad) keep a
# 10M test-circulation pool for dev/test accounts, so their contingency bucket stays 10M (sum=100M).
# MAINNET + the launch/regenesis script (init-gembad-multinode.sh) use ALLOC_CONTINGENCY=20M and NO
# circulation, funding the validators' self-bond + early participants from the FOUNDER / DAO reserve.
ALLOC_LIQUIDITY="10000000"

# Validator funding: each genesis validator self-bonds SELF_BOND_GMB carved from the FOUNDER
# allocation (consensus power comes from founder-seeded stake, never from a reserve). The founder
# EOA keeps ALLOC_FOUNDER minus the validators' entry. Early participants likewise receive GMB
# from the founder / DAO reserve, not from a standing circulation bucket.
SELF_BOND_GMB="10000"            # 10,000 GMB self-bonded per genesis validator (regenesis §11:
                                 # the max entry self-bond; the valgate max-self-bond cap rejects above 10,000)
MIN_SELF_BOND_GMB="1000"   # x/valgate floor (gentx --min-self-delegation must be >= this)
