package types

// The fee-split module implements GembaBlockchain's custom fee distribution
// (CLAUDE.md §5.4, §6): of the EIP-1559 fees collected each block, 60% go to
// validators/delegators (via the normal distribution flow) and 40% are routed to
// the faucet (the public/municipal reserve), so the faucet refills from real use.
// It only TRANSFERS fees that were already collected — it never mints.
const (
	// ModuleName is the module name.
	ModuleName = "feesplit"

	// StoreKey is the module's KVStore key.
	StoreKey = ModuleName

	// RouterKey routes messages for this module.
	RouterKey = ModuleName

	// DefaultFaucetAccount is the module account name that receives the 40%
	// faucet share. In Phase 3 the faucet becomes a Solidity contract; for now
	// it is a plain module account.
	DefaultFaucetAccount = "faucet"
)

// ParamsKey is the single KVStore key under which params are stored (JSON).
var ParamsKey = []byte{0x01}
