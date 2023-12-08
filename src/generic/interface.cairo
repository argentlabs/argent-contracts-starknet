#[starknet::interface]
trait IRecoveryAccount<TContractState> {
    fn toggle_escape(ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64);
    fn trigger_escape_signer(ref self: TContractState, target_signer: felt252, new_signer: felt252);
    fn escape_signer(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
}
