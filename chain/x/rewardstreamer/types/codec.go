package types

import (
	"github.com/cosmos/cosmos-sdk/codec"
	cdctypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/msgservice"
)

// RegisterInterfaces registers the module's Msg implementations so governance can
// execute MsgUpdateParams (audit finding #5) and MsgUpdateFormulaParams (audit M2).
func RegisterInterfaces(registry cdctypes.InterfaceRegistry) {
	registry.RegisterImplementations((*sdk.Msg)(nil), &MsgUpdateParams{}, &MsgUpdateFormulaParams{})
	msgservice.RegisterMsgServiceDesc(registry, &_Msg_serviceDesc)
}

// RegisterLegacyAminoCodec is a no-op (proto-only module).
func RegisterLegacyAminoCodec(*codec.LegacyAmino) {}
