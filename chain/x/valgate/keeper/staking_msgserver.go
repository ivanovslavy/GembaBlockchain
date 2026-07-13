package keeper

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
)

// CapEnforcingStakingMsgServer wraps the staking MsgServer so the §6 per-validator daily
// bond-increase cap (x/valgate) is enforced on the paths the ante decorator CANNOT see —
// specifically the EVM staking precompile (0x…0800), whose delegate/redelegate call the staking
// MsgServer DIRECTLY during EVM execution, AFTER the ante phase (SEC audit M1). The ante still
// enforces the cap for ordinary Cosmos MsgDelegate/MsgBeginRedelegate, so wiring this wrapper ONLY
// into the staking precompile (never the app-wide msg router) means each path is checked exactly
// once — no double counting.
//
// Everything except Delegate/BeginRedelegate passes straight through to the embedded MsgServer
// (CreateValidator's self-bond caps are enforced separately by the AfterValidatorCreated hook).
type CapEnforcingStakingMsgServer struct {
	stakingtypes.MsgServer // embedded: all other methods pass through unchanged
	vk                     Keeper
}

var _ stakingtypes.MsgServer = CapEnforcingStakingMsgServer{}

// NewCapEnforcingStakingMsgServer wraps `inner` (typically stakingkeeper.NewMsgServerImpl(...)) so
// delegate/redelegate first check the valgate daily cap. Wire it into the staking precompile only.
func NewCapEnforcingStakingMsgServer(inner stakingtypes.MsgServer, vk Keeper) stakingtypes.MsgServer {
	return CapEnforcingStakingMsgServer{MsgServer: inner, vk: vk}
}

// Delegate enforces the daily cap against the destination validator, then delegates. An over-cap
// delegation returns an error, which rolls back the EVM sub-call — the same rejection an ante-gated
// Cosmos MsgDelegate would get.
func (s CapEnforcingStakingMsgServer) Delegate(goCtx context.Context, msg *stakingtypes.MsgDelegate) (*stakingtypes.MsgDelegateResponse, error) {
	if valAddr, err := sdk.ValAddressFromBech32(msg.ValidatorAddress); err == nil && !msg.Amount.Amount.IsNil() {
		if err := s.vk.CheckAndRecordDailyBond(sdk.UnwrapSDKContext(goCtx), valAddr, msg.Amount.Amount); err != nil {
			return nil, err
		}
	}
	return s.MsgServer.Delegate(goCtx, msg)
}

// BeginRedelegate enforces the daily cap against the DESTINATION validator (the one whose bonded
// stake — and thus voting power — increases), then redelegates.
func (s CapEnforcingStakingMsgServer) BeginRedelegate(goCtx context.Context, msg *stakingtypes.MsgBeginRedelegate) (*stakingtypes.MsgBeginRedelegateResponse, error) {
	if valAddr, err := sdk.ValAddressFromBech32(msg.ValidatorDstAddress); err == nil && !msg.Amount.Amount.IsNil() {
		if err := s.vk.CheckAndRecordDailyBond(sdk.UnwrapSDKContext(goCtx), valAddr, msg.Amount.Amount); err != nil {
			return nil, err
		}
	}
	return s.MsgServer.BeginRedelegate(goCtx, msg)
}
