// Package wiring holds cross-module wiring invariants for the gembad binary.
//
// The money-routing BeginBlock order (audit L1) is a supply/reward invariant:
//
//	feesplit → rewardstreamer → tailreward → distribution
//
// feesplit must split the previous block's fees BEFORE the reward stream tops the
// fee collector up (else the 40% faucet share would skim the validator reward),
// and every reward must land in the fee collector BEFORE distribution pays it
// out (else it is paid a block late or double-counted). The order lives only in
// a hand-written list in the (patched) evmd app constructor, so the constructor
// calls ValidateBeginBlockOrder on the resolved order and refuses to boot on a
// violation — a silent reorder in a future upstream merge becomes a loud panic.
package wiring

import (
	"fmt"

	distrtypes "github.com/cosmos/cosmos-sdk/x/distribution/types"

	feesplittypes "github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/types"
	rewardstreamertypes "github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
	tailrewardtypes "github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

// requiredBeginBlockOrder is the money-routing chain, in the order it must run.
var requiredBeginBlockOrder = []string{
	feesplittypes.ModuleName,
	rewardstreamertypes.ModuleName,
	tailrewardtypes.ModuleName,
	distrtypes.ModuleName,
}

// ValidateBeginBlockOrder checks that the resolved begin-blocker order contains
// every money-routing module exactly once and in the required relative order
// (other modules may interleave freely). Returns a descriptive error on any
// violation; the app constructor panics on it.
func ValidateBeginBlockOrder(order []string) error {
	pos := make(map[string]int, len(requiredBeginBlockOrder))
	for i, name := range order {
		for _, want := range requiredBeginBlockOrder {
			if name != want {
				continue
			}
			if at, dup := pos[name]; dup {
				return fmt.Errorf("wiring: begin-blocker order lists %q twice (positions %d and %d)", name, at, i)
			}
			pos[name] = i
		}
	}
	for _, want := range requiredBeginBlockOrder {
		if _, ok := pos[want]; !ok {
			return fmt.Errorf("wiring: begin-blocker order is missing %q (required: %v)", want, requiredBeginBlockOrder)
		}
	}
	for i := 1; i < len(requiredBeginBlockOrder); i++ {
		prev, cur := requiredBeginBlockOrder[i-1], requiredBeginBlockOrder[i]
		if pos[prev] >= pos[cur] {
			return fmt.Errorf(
				"wiring: begin-blocker order violation — %q (position %d) must run before %q (position %d); required: %v",
				prev, pos[prev], cur, pos[cur], requiredBeginBlockOrder,
			)
		}
	}
	return nil
}
