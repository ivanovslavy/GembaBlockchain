package tailreward

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/grpc-ecosystem/grpc-gateway/runtime"

	abci "github.com/cometbft/cometbft/abci/types"

	"cosmossdk.io/core/appmodule"

	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

const consensusVersion = 1

var (
	_ module.AppModule          = AppModule{} //nolint:staticcheck // legacy interface, intentional
	_ module.AppModuleBasic     = AppModule{}
	_ module.HasABCIGenesis     = AppModule{}
	_ module.HasServices        = AppModule{}
	_ appmodule.HasBeginBlocker = AppModule{}
)

// AppModule wires the tail reward into the application module manager.
type AppModule struct {
	keeper keeper.Keeper
}

// NewAppModule creates the tail reward app module.
func NewAppModule(k keeper.Keeper) AppModule { return AppModule{keeper: k} }

func (AppModule) Name() string                                                { return types.ModuleName }
func (AppModule) RegisterLegacyAminoCodec(*codec.LegacyAmino)                 {}
func (AppModule) RegisterInterfaces(codectypes.InterfaceRegistry)             {}
func (AppModule) RegisterGRPCGatewayRoutes(client.Context, *runtime.ServeMux) {}
func (AppModule) RegisterServices(module.Configurator)                        {}
func (AppModule) ConsensusVersion() uint64                                    { return consensusVersion }
func (AppModule) IsAppModule()                                                {}
func (AppModule) IsOnePerModuleType()                                         {}

func (AppModule) DefaultGenesis(codec.JSONCodec) json.RawMessage {
	bz, err := json.Marshal(types.DefaultGenesis())
	if err != nil {
		panic(err)
	}
	return bz
}

func (AppModule) ValidateGenesis(_ codec.JSONCodec, _ client.TxEncodingConfig, bz json.RawMessage) error {
	var gs types.GenesisState
	if err := json.Unmarshal(bz, &gs); err != nil {
		return fmt.Errorf("failed to unmarshal %s genesis: %w", types.ModuleName, err)
	}
	return gs.Validate()
}

func (am AppModule) InitGenesis(ctx sdk.Context, _ codec.JSONCodec, data json.RawMessage) []abci.ValidatorUpdate {
	var gs types.GenesisState
	if err := json.Unmarshal(data, &gs); err != nil {
		panic(err)
	}
	am.keeper.InitGenesis(ctx, gs)
	return []abci.ValidatorUpdate{}
}

func (am AppModule) ExportGenesis(ctx sdk.Context, _ codec.JSONCodec) json.RawMessage {
	bz, err := json.Marshal(am.keeper.ExportGenesis(ctx))
	if err != nil {
		panic(err)
	}
	return bz
}

// BeginBlock streams the per-block tail reward (see keeper.BeginBlock for ordering).
func (am AppModule) BeginBlock(ctx context.Context) error {
	return am.keeper.BeginBlock(sdk.UnwrapSDKContext(ctx))
}
