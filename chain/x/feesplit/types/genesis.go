package types

// GenesisState carries the module params.
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
