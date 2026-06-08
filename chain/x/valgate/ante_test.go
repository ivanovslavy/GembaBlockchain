package valgate_test

import (
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
	return &stakingtypes.MsgCreateValidator{Value: sdk.NewCoin("agmb", math.NewInt(gmb).Mul(oneGmb))}
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
