package valgate_test

import (
	"context"
	"testing"

	"cosmossdk.io/math"
	protov2 "google.golang.org/protobuf/proto"

	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdktestutil "github.com/cosmos/cosmos-sdk/testutil"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/x/authz"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/stretchr/testify/require"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

var oneGmb = math.NewInt(1_000_000_000_000_000_000)

type mockTx struct{ msgs []sdk.Msg }

func (m mockTx) GetMsgs() []sdk.Msg                          { return m.msgs }
func (m mockTx) GetMsgsV2() ([]protov2.Message, error)       { return nil, nil }

func setupKeeper(t *testing.T) (sdk.Context, keeper.Keeper) {
	key := storetypes.NewKVStoreKey(types.StoreKey)
	tkey := storetypes.NewTransientStoreKey("transient_valgate")
	ctx := sdktestutil.DefaultContext(key, tkey)
	cdc := codec.NewProtoCodec(codectypes.NewInterfaceRegistry())
	k := keeper.NewKeeper(cdc, key, "gov")
	require.NoError(t, k.SetParams(ctx, types.DefaultParams())) // 1000 GMB
	return ctx, k
}

func cv(gmb int64) sdk.Msg {
	amt := math.NewInt(gmb).Mul(oneGmb)
	return &stakingtypes.MsgCreateValidator{Value: sdk.NewCoin("agmb", amt), MinSelfDelegation: amt}
}
func next(ctx sdk.Context, _ sdk.Tx, _ bool) (sdk.Context, error) { return ctx, nil }

// TestMinSelfBondEnforced: below the 1,000 GMB floor is rejected; >= is accepted.
func TestMinSelfBondEnforced(t *testing.T) {
	ctx, k := setupKeeper(t)
	d := valgate.NewMinSelfBondDecorator(k)

	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(999)}}, false, next)
	require.Error(t, err, "999 GMB self-bond must be rejected")

	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(1000)}}, false, next)
	require.NoError(t, err, "exactly 1000 GMB must be accepted")

	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(5000)}}, false, next)
	require.NoError(t, err, "above the floor must be accepted")

	_, err = d.AnteHandle(ctx, mockTx{nil}, false, next)
	require.NoError(t, err, "a tx without MsgCreateValidator must pass")
}

type mockStaking struct {
	msd    math.Int
	tokens math.Int // initial self-bond seen by AfterValidatorCreated (0/nil = unset)
}

func (m mockStaking) GetValidator(_ context.Context, _ sdk.ValAddress) (stakingtypes.Validator, error) {
	return stakingtypes.Validator{MinSelfDelegation: m.msd, Tokens: m.tokens}, nil
}

// TestHookEnforcesMinSelfDelegation: the staking hook rejects a below-floor MinSelfDelegation
// regardless of the creation path — this is what covers the EVM staking precompile, which the
// ante decorator cannot see (audit finding #1).
func TestHookEnforcesMinSelfDelegation(t *testing.T) {
	key := storetypes.NewKVStoreKey(types.StoreKey)
	tkey := storetypes.NewTransientStoreKey("transient_valgate")
	ctx := sdktestutil.DefaultContext(key, tkey)
	cdc := codec.NewProtoCodec(codectypes.NewInterfaceRegistry())

	low := keeper.NewKeeper(cdc, key, "gov").WithStakingKeeper(mockStaking{msd: math.NewInt(1)})
	require.NoError(t, low.SetParams(ctx, types.DefaultParams())) // 1000 GMB floor
	require.Error(t, low.Hooks().AfterValidatorCreated(ctx, sdk.ValAddress("validator-address-x")),
		"below-floor MinSelfDelegation must be rejected at the staking hook (covers the precompile path)")

	ok := keeper.NewKeeper(cdc, key, "gov").WithStakingKeeper(mockStaking{msd: math.NewInt(1000).Mul(oneGmb)})
	require.NoError(t, ok.Hooks().AfterValidatorCreated(ctx, sdk.ValAddress("validator-address-x")))
}

// TestMinSelfDelegationFloor: a creation at the floor but with MinSelfDelegation below it must
// be rejected, so staking permanently enforces the floor (audit finding #4).
func TestMinSelfDelegationFloor(t *testing.T) {
	ctx, k := setupKeeper(t)
	d := valgate.NewMinSelfBondDecorator(k)
	msg := &stakingtypes.MsgCreateValidator{
		Value:             sdk.NewCoin("agmb", math.NewInt(1000).Mul(oneGmb)), // at the floor
		MinSelfDelegation: math.NewInt(1),                                     // but commits ~nothing
	}
	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{msg}}, false, next)
	require.Error(t, err, "MinSelfDelegation below the floor must be rejected")
}

// TestGovernanceTunable: raising the param via SetParams (gov path) changes enforcement
// with no restart.
func TestGovernanceTunable(t *testing.T) {
	ctx, k := setupKeeper(t)
	require.NoError(t, k.SetParams(ctx, types.Params{MinSelfBond: math.NewInt(5000).Mul(oneGmb)}))
	d := valgate.NewMinSelfBondDecorator(k)

	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(1000)}}, false, next)
	require.Error(t, err, "1000 must now be rejected (floor raised to 5000)")

	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(5000)}}, false, next)
	require.NoError(t, err, "5000 accepted at the new floor")
}

// TestMaxSelfBondEnforced: at the 10,000 GMB cap is accepted; above it is rejected — the
// §5.2 anti-domination cap (a new validator can't enter with a huge self-stake).
func TestMaxSelfBondEnforced(t *testing.T) {
	ctx, k := setupKeeper(t) // default params: min 1000, max 10000
	d := valgate.NewMinSelfBondDecorator(k)

	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(10000)}}, false, next)
	require.NoError(t, err, "exactly 10000 GMB (the cap) must be accepted")

	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(10001)}}, false, next)
	require.Error(t, err, "10001 GMB self-bond must be rejected (above the max)")

	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(1_000_000)}}, false, next)
	require.Error(t, err, "a whale entering with 1M GMB must be rejected (anti-domination)")
}

// TestMaxSelfBondZeroMeansNoCap: max_self_bond = 0 disables the cap.
func TestMaxSelfBondZeroMeansNoCap(t *testing.T) {
	ctx, k := setupKeeper(t)
	require.NoError(t, k.SetParams(ctx, types.Params{
		MinSelfBond: math.NewInt(1000).Mul(oneGmb),
		MaxSelfBond: math.ZeroInt(), // no cap
	}))
	d := valgate.NewMinSelfBondDecorator(k)
	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{cv(1_000_000)}}, false, next)
	require.NoError(t, err, "with max=0 (no cap) a large self-bond must be accepted")
}

// TestHookEnforcesMaxSelfBond: the staking hook also caps the initial self-bond — covers the
// EVM staking precompile path (val.Tokens at creation == the self-bond).
func TestHookEnforcesMaxSelfBond(t *testing.T) {
	key := storetypes.NewKVStoreKey(types.StoreKey)
	tkey := storetypes.NewTransientStoreKey("transient_valgate")
	ctx := sdktestutil.DefaultContext(key, tkey)
	cdc := codec.NewProtoCodec(codectypes.NewInterfaceRegistry())
	msd := math.NewInt(1000).Mul(oneGmb)

	over := keeper.NewKeeper(cdc, key, "gov").WithStakingKeeper(mockStaking{msd: msd, tokens: math.NewInt(10001).Mul(oneGmb)})
	require.NoError(t, over.SetParams(ctx, types.DefaultParams()))
	require.Error(t, over.Hooks().AfterValidatorCreated(ctx, sdk.ValAddress("validator-address-x")),
		"a 10001 GMB initial self-bond must be rejected at the hook (precompile path)")

	atCap := keeper.NewKeeper(cdc, key, "gov").WithStakingKeeper(mockStaking{msd: msd, tokens: math.NewInt(10000).Mul(oneGmb)})
	require.NoError(t, atCap.SetParams(ctx, types.DefaultParams()))
	require.NoError(t, atCap.Hooks().AfterValidatorCreated(ctx, sdk.ValAddress("validator-address-x")),
		"exactly at the cap must be accepted")
}

// TestMaxSelfBondThroughAuthzMsgExec: the cap also applies to a MsgCreateValidator nested in
// an authz MsgExec.
func TestMaxSelfBondThroughAuthzMsgExec(t *testing.T) {
	ctx, k := setupKeeper(t)
	d := valgate.NewMinSelfBondDecorator(k)
	grantee := sdk.AccAddress([]byte("grantee-------------"))
	exec := authz.NewMsgExec(grantee, []sdk.Msg{cv(10001)})
	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{&exec}}, false, next)
	require.Error(t, err, "above-cap CreateValidator nested in MsgExec must be rejected")
}

// TestMinSelfBondThroughAuthzMsgExec: a MsgCreateValidator nested in an authz MsgExec must
// still be subject to the floor — closes the audit finding #9 bypass.
func TestMinSelfBondThroughAuthzMsgExec(t *testing.T) {
	ctx, k := setupKeeper(t)
	d := valgate.NewMinSelfBondDecorator(k)
	grantee := sdk.AccAddress([]byte("grantee-------------"))

	exec := authz.NewMsgExec(grantee, []sdk.Msg{cv(999)})
	_, err := d.AnteHandle(ctx, mockTx{[]sdk.Msg{&exec}}, false, next)
	require.Error(t, err, "below-floor CreateValidator nested in MsgExec must be rejected (finding #9)")

	execOk := authz.NewMsgExec(grantee, []sdk.Msg{cv(1000)})
	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{&execOk}}, false, next)
	require.NoError(t, err, "at-floor CreateValidator nested in MsgExec must pass")

	// doubly nested is also caught
	inner := authz.NewMsgExec(grantee, []sdk.Msg{cv(999)})
	outer := authz.NewMsgExec(grantee, []sdk.Msg{&inner})
	_, err = d.AnteHandle(ctx, mockTx{[]sdk.Msg{&outer}}, false, next)
	require.Error(t, err, "doubly-nested below-floor must be rejected")
}
