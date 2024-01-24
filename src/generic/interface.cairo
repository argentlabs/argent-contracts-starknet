use argent::common::signer_signature::Signer;

#[starknet::interface]
trait IRecoveryAccount<TContractState> {
    fn toggle_escape(ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64);
    fn trigger_escape_signer(ref self: TContractState, target_signer: Signer, new_signer: Signer);
    fn escape_signer(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
}
