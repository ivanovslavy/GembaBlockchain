package types

// GenesisState is the module's genesis. The 20M reserve itself is funded via the
// bank module genesis (coins allocated to this module's account), so genesis here
// only carries params.
type GenesisState struct {
	Params Params `json:"params"`
}

// DefaultGenesis returns the default genesis state.
func DefaultGenesis() *GenesisState {
	return &GenesisState{Params: DefaultParams()}
}

// Validate validates the genesis state.
func (gs GenesisState) Validate() error {
	return gs.Params.Validate()
}
