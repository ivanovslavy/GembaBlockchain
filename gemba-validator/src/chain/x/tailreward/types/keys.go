package types

// The tail reward is GembaBlockchain's POST-RESERVE validator-reward mechanism
// (docs/risks.md ADR-008 mechanism (b)). After the pre-minted 20M validator
// reserve is exhausted (~10 yrs, see x/rewardstreamer), this module sustains a
// baseline validator reward by RECIRCULATING already-circulating GMB: governance
// funds this module's account from the fee-funded reserves (the faucet's 40% fee
// inflow / DAO surplus), and each block a slice is streamed to the fee_collector
// for the distribution module to pay validators.
//
// Like the reward streamer it only ever TRANSFERS pre-existing GMB — it NEVER
// mints — so total supply is unchanged and inflation stays exactly 0% (invariant
// §3.1). It is DISABLED by default and is activated by governance when the main
// reserve nears depletion and the bonded ratio needs defending (ADR-008).
const (
	// ModuleName is the module name. The module's own account is the recirculation
	// buffer, funded by governance from fee-funded reserves; only this module's
	// BeginBlocker can spend it (no unilateral key — §3.6).
	ModuleName = "tailreward"

	StoreKey = ModuleName

	RouterKey = ModuleName
)

// ParamsKey is the single KVStore key under which params are stored (JSON).
var ParamsKey = []byte{0x01}
