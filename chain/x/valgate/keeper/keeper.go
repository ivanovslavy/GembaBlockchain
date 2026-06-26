package keeper

import (
	"context"
	"fmt"

	"cosmossdk.io/log/v2"
	"cosmossdk.io/math"

	"github.com/cosmos/cosmos-sdk/codec"
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

// StakingKeeper is the read-only slice of the staking keeper the valgate hook needs to read a
// just-created validator's committed MinSelfDelegation.
type StakingKeeper interface {
	GetValidator(ctx context.Context, addr sdk.ValAddress) (stakingtypes.Validator, error)
}

// Keeper stores the governance-tunable validator-gate params.
type Keeper struct {
	cdc           codec.BinaryCodec
	storeKey      storetypes.StoreKey
	authority     string // the gov module account; only it may UpdateParams
	stakingKeeper StakingKeeper
}

// NewKeeper builds the valgate keeper.
func NewKeeper(cdc codec.BinaryCodec, storeKey storetypes.StoreKey, authority string) Keeper {
	return Keeper{cdc: cdc, storeKey: storeKey, authority: authority}
}

// WithStakingKeeper injects the read-only staking keeper used by the AfterValidatorCreated hook
// (which enforces the §5.2 floor on BOTH the Cosmos and EVM-precompile creation paths — audit
// finding #1). Called by the app AFTER the staking keeper exists and BEFORE SetHooks. valgate's
// other features (params, ante, msg server) don't need it, so NewKeeper stays minimal.
func (k Keeper) WithStakingKeeper(sk StakingKeeper) Keeper {
	k.stakingKeeper = sk
	return k
}

// GetAuthority returns the gov authority address.
func (k Keeper) GetAuthority() string { return k.authority }

func (k Keeper) Logger(ctx sdk.Context) log.Logger {
	return ctx.Logger().With("module", "x/"+types.ModuleName)
}

// GetParams reads the module params (proto-encoded; default if unset).
func (k Keeper) GetParams(ctx sdk.Context) types.Params {
	bz := ctx.KVStore(k.storeKey).Get(types.ParamsKey)
	if bz == nil {
		return types.DefaultParams()
	}
	var p types.Params
	k.cdc.MustUnmarshal(bz, &p)
	// Migration safety: params stored before max_self_bond existed unmarshal with a nil
	// MaxSelfBond. Default it (also keeps the math.Int non-nil so marshaling can't panic).
	// A live chain can then set the real cap via a governance MsgUpdateParams.
	if p.MaxSelfBond.IsNil() {
		p.MaxSelfBond = types.DefaultParams().MaxSelfBond
	}
	if p.MaxDailyBondIncrease.IsNil() {
		p.MaxDailyBondIncrease = types.DefaultParams().MaxDailyBondIncrease
	}
	return p
}

// CheckAndRecordDailyBond enforces the §6 per-validator daily bond-increase cap. Called from the
// ante for each stake-increasing message (MsgDelegate, MsgBeginRedelegate dst, self-bond top-ups
// of an already-created validator). DETERMINISTIC: the "day" comes from the block header time,
// never wall-clock, so every node computes the same result.
//
// If the cap is 0/nil → no limit. Otherwise it sums the validator's increases within the current
// day; if this one would push the day's total over the cap it returns an error (the tx is rejected
// — a normal failure, the chain keeps running, NEVER a panic). On success it records the new total.
// Writes only commit in DeliverTx, atomically with the tx (CheckTx is a dry run).
func (k Keeper) CheckAndRecordDailyBond(ctx sdk.Context, valoper sdk.ValAddress, amount math.Int) error {
	limit := k.GetParams(ctx).MaxDailyBondIncrease
	if limit.IsNil() || !limit.IsPositive() { // 0/nil = no cap
		return nil
	}
	used := k.dailyBondUsed(ctx, valoper)
	if used.Add(amount).GT(limit) {
		return fmt.Errorf(
			"validator %s would add %s to its stake today, exceeding the %s/day max bond increase (governance-set, x/valgate §6); already added %s today",
			valoper, amount, limit, used,
		)
	}
	k.setDailyBondUsed(ctx, valoper, used.Add(amount))
	return nil
}

// RemainingDailyBond returns how much MORE may be bonded to `valoper` today (0 at the cap; a huge
// number if there is no cap). Lets an auto-compound clamp instead of failing.
func (k Keeper) RemainingDailyBond(ctx sdk.Context, valoper sdk.ValAddress) math.Int {
	limit := k.GetParams(ctx).MaxDailyBondIncrease
	if limit.IsNil() || !limit.IsPositive() {
		return math.NewIntFromUint64(^uint64(0))
	}
	rem := limit.Sub(k.dailyBondUsed(ctx, valoper))
	if rem.IsNegative() {
		return math.ZeroInt()
	}
	return rem
}

// dailyBondUsed reads the amount bonded to `valoper` within the CURRENT (block-time) day.
func (k Keeper) dailyBondUsed(ctx sdk.Context, valoper sdk.ValAddress) math.Int {
	day := uint64(ctx.BlockTime().Unix() / 86400)
	bz := ctx.KVStore(k.storeKey).Get(k.dailyBondKey(valoper))
	used := math.ZeroInt()
	if bz != nil && len(bz) >= 8 && sdk.BigEndianToUint64(bz[:8]) == day {
		_ = used.Unmarshal(bz[8:])
	}
	return used
}

func (k Keeper) setDailyBondUsed(ctx sdk.Context, valoper sdk.ValAddress, total math.Int) {
	day := uint64(ctx.BlockTime().Unix() / 86400)
	amtBz, err := total.Marshal()
	if err != nil {
		return // never panic in consensus-critical state writes
	}
	ctx.KVStore(k.storeKey).Set(k.dailyBondKey(valoper), append(sdk.Uint64ToBigEndian(day), amtBz...))
}

func (k Keeper) dailyBondKey(valoper sdk.ValAddress) []byte {
	return append(append([]byte{}, types.DailyBondPrefix...), valoper.Bytes()...)
}

// SetParams validates and writes the module params.
func (k Keeper) SetParams(ctx sdk.Context, p types.Params) error {
	if err := p.Validate(); err != nil {
		return err
	}
	ctx.KVStore(k.storeKey).Set(types.ParamsKey, k.cdc.MustMarshal(&p))
	return nil
}
