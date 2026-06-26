package keeper

import (
	"context"

	"cosmossdk.io/log/v2"

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
	return p
}

// SetParams validates and writes the module params.
func (k Keeper) SetParams(ctx sdk.Context, p types.Params) error {
	if err := p.Validate(); err != nil {
		return err
	}
	ctx.KVStore(k.storeKey).Set(types.ParamsKey, k.cdc.MustMarshal(&p))
	return nil
}
