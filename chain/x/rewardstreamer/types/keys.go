package types

// The reward streamer is GembaBlockchain's zero-inflation validator-reward
// mechanism (CLAUDE.md §5.4, §4.3; docs/risks.md ADR-008). Each block it moves a
// fixed slice of GMB from the pre-minted 20M validator-reward reserve into the
// fee_collector, where the distribution module pays it to validators/delegators.
// It only ever TRANSFERS pre-minted coins — it never mints — so total supply is
// unchanged and inflation stays exactly 0% (invariant §3.1).
const (
	// ModuleName is the module name. The module's own account holds the
	// validator-reward reserve; only this module's BeginBlocker can spend it
	// (no unilateral key — §3.6).
	ModuleName = "rewardstreamer"

	// StoreKey is the module's KVStore key.
	StoreKey = ModuleName

	// RouterKey routes messages for this module.
	RouterKey = ModuleName
)

// ParamsKey is the single KVStore key under which params are stored (JSON).
var ParamsKey = []byte{0x01}
