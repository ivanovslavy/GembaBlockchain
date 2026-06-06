package types

// The valgate module enforces a governance-tunable minimum validator self-bond
// (CLAUDE.md §5.2 "growing threshold"). An ante decorator rejects MsgCreateValidator
// whose self-delegation is below Params.MinSelfBond; governance changes the floor via
// MsgUpdateParams — no chain restart needed.
const (
	ModuleName = "valgate"
	StoreKey   = ModuleName
	RouterKey  = ModuleName
)

// ParamsKey is the single KVStore key under which params are stored (proto-encoded).
var ParamsKey = []byte{0x01}
