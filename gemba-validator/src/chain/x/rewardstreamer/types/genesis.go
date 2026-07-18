package types

// GenesisState is the module's genesis. The 20M reserve itself is funded via the
// bank module genesis (coins allocated to this module's account), so genesis here
// only carries params.
type GenesisState struct {
	Params Params `json:"params"`
	// FormulaParams drives the live capped per-validator reward stream. It is carried in genesis
	// (SEC audit M2) so it survives export/import instead of silently resetting to build-time
	// defaults on every upgrade/regenesis. Omitted → DefaultFormulaParams (see ResolvedFormulaParams).
	FormulaParams FormulaParams `json:"formula_params"`
}

// DefaultGenesis returns the default genesis state.
func DefaultGenesis() *GenesisState {
	return &GenesisState{Params: DefaultParams(), FormulaParams: DefaultFormulaParams()}
}

// ResolvedFormulaParams returns the genesis FormulaParams, substituting defaults when the block was
// omitted from genesis JSON (detected by a nil RatePerDay — a struct that was never populated).
func (gs GenesisState) ResolvedFormulaParams() FormulaParams {
	if gs.FormulaParams.RatePerDay.IsNil() {
		return DefaultFormulaParams()
	}
	return gs.FormulaParams
}

// Validate validates the genesis state.
func (gs GenesisState) Validate() error {
	if err := gs.Params.Validate(); err != nil {
		return err
	}
	return gs.ResolvedFormulaParams().Validate()
}
