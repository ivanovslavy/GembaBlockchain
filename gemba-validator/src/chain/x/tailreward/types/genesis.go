package types

// GenesisState carries the module params. The recirculation buffer itself is
// funded later by governance (moving GMB from fee-funded reserves into this
// module's account), so genesis here only carries params.
type GenesisState struct {
	Params Params `json:"params"`
}

// DefaultGenesis returns the default (disabled) genesis state.
func DefaultGenesis() *GenesisState {
	return &GenesisState{Params: DefaultParams()}
}

// Validate validates the genesis state.
func (gs GenesisState) Validate() error {
	return gs.Params.Validate()
}
