package types

// Event types emitted by the reward streamer.
const (
	EventTypeStreamReward        = "stream_reward"
	EventTypeUpdateFormulaParams = "update_formula_params"

	AttributeKeyAmount         = "amount"
	AttributeKeyReserveBalance = "reserve_balance"
	AttributeKeyDepleted       = "reserve_depleted"
	AttributeKeyAuthority      = "authority"
	AttributeKeyEnabled        = "enabled"
)
