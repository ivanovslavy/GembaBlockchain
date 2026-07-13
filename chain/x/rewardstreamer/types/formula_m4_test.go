package types

import (
	"encoding/json"
	"testing"

	"cosmossdk.io/math"
)

// SEC audit M4: the aggregate per-day budget prorates to a positive per-block ceiling, and 0/nil
// means "no aggregate cap".
func TestFormulaParams_MaxTotalPerBlock(t *testing.T) {
	fp := DefaultFormulaParams() // 5,479 GMB/day over 28,800 blocks
	pb := fp.MaxTotalPerBlock()
	if !pb.IsPositive() {
		t.Fatalf("expected positive per-block budget, got %s", pb)
	}
	want := fp.MaxTotalPerDay.Quo(math.NewIntFromUint64(fp.BlocksPerDay))
	if !pb.Equal(want) {
		t.Fatalf("per-block budget = %s, want %s", pb, want)
	}
	// 0 aggregate cap → no ceiling
	fp.MaxTotalPerDay = math.ZeroInt()
	if z := fp.MaxTotalPerBlock(); !z.IsZero() {
		t.Fatalf("zero MaxTotalPerDay must yield zero per-block ceiling, got %s", z)
	}
}

// SEC audit M2: FormulaParams survives a genesis JSON round-trip, and an omitted formula_params
// block resolves to the (valid) defaults rather than a zero/invalid struct.
func TestGenesisState_FormulaRoundTrip(t *testing.T) {
	gs := DefaultGenesis()
	bz, err := json.Marshal(gs)
	if err != nil {
		t.Fatal(err)
	}
	var back GenesisState
	if err := json.Unmarshal(bz, &back); err != nil {
		t.Fatal(err)
	}
	if err := back.Validate(); err != nil {
		t.Fatalf("round-tripped genesis must validate: %v", err)
	}
	if !back.ResolvedFormulaParams().MaxTotalPerDay.Equal(DefaultFormulaParams().MaxTotalPerDay) {
		t.Fatalf("MaxTotalPerDay did not survive round-trip")
	}

	// Omitted formula_params (legacy genesis) → defaults, still valid.
	var omitted GenesisState
	if err := json.Unmarshal([]byte(`{"params":`+mustParamsJSON(t)+`}`), &omitted); err != nil {
		t.Fatal(err)
	}
	if !omitted.FormulaParams.RatePerDay.IsNil() {
		t.Fatalf("expected nil RatePerDay for omitted formula_params")
	}
	if err := omitted.Validate(); err != nil {
		t.Fatalf("genesis omitting formula_params must validate via defaults: %v", err)
	}
	if !omitted.ResolvedFormulaParams().Enabled {
		t.Fatalf("resolved formula params should be the enabled defaults")
	}
}

func mustParamsJSON(t *testing.T) string {
	t.Helper()
	bz, err := json.Marshal(DefaultParams())
	if err != nil {
		t.Fatal(err)
	}
	return string(bz)
}
