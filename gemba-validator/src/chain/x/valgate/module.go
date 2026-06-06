package valgate

import (
	"encoding/json"
	"fmt"

	"github.com/grpc-ecosystem/grpc-gateway/runtime"

	abci "github.com/cometbft/cometbft/abci/types"

	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

const consensusVersion = 1

var (
	_ module.AppModule      = AppModule{} //nolint:staticcheck // legacy interface, intentional
	_ module.AppModuleBasic = AppModule{}
	_ module.HasABCIGenesis = AppModule{}
	_ module.HasServices    = AppModule{}
)

// AppModule wires the validator-gate (min self-bond) into the module manager.
type AppModule struct {
	keeper keeper.Keeper
}

// NewAppModule creates the valgate app module.
func NewAppModule(k keeper.Keeper) AppModule { return AppModule{keeper: k} }

func (AppModule) Name() string                                                { return types.ModuleName }
func (AppModule) RegisterLegacyAminoCodec(*codec.LegacyAmino)                 {}
func (AppModule) RegisterInterfaces(reg codectypes.InterfaceRegistry)         { types.RegisterInterfaces(reg) }
func (AppModule) RegisterGRPCGatewayRoutes(client.Context, *runtime.ServeMux) {}
func (AppModule) ConsensusVersion() uint64                                    { return consensusVersion }
func (AppModule) IsAppModule()                                                {}
func (AppModule) IsOnePerModuleType()                                         {}

func (am AppModule) RegisterServices(cfg module.Configurator) {
	types.RegisterMsgServer(cfg.MsgServer(), keeper.NewMsgServerImpl(am.keeper))
	types.RegisterQueryServer(cfg.QueryServer(), am.keeper)
}

func (AppModule) DefaultGenesis(cdc codec.JSONCodec) json.RawMessage {
	return cdc.MustMarshalJSON(types.DefaultGenesis())
}

func (AppModule) ValidateGenesis(cdc codec.JSONCodec, _ client.TxEncodingConfig, bz json.RawMessage) error {
	var gs types.GenesisState
	if err := cdc.UnmarshalJSON(bz, &gs); err != nil {
		return fmt.Errorf("failed to unmarshal %s genesis: %w", types.ModuleName, err)
	}
	return gs.Validate()
}

func (am AppModule) InitGenesis(ctx sdk.Context, cdc codec.JSONCodec, data json.RawMessage) []abci.ValidatorUpdate {
	var gs types.GenesisState
	cdc.MustUnmarshalJSON(data, &gs)
	am.keeper.InitGenesis(ctx, gs)
	return []abci.ValidatorUpdate{}
}

func (am AppModule) ExportGenesis(ctx sdk.Context, cdc codec.JSONCodec) json.RawMessage {
	return cdc.MustMarshalJSON(am.keeper.ExportGenesis(ctx))
}
