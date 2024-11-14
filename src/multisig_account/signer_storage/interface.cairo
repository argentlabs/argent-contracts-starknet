#[starknet::interface]
trait ISignerList<TContractState> {
    fn add_signer(ref self: TContractState, signer_to_add: felt252, last_signer: felt252);
    fn add_signers(ref self: TContractState, signers_to_add: Span<felt252>, last_signer: felt252);
    fn remove_signer(ref self: TContractState, signer_to_remove: felt252, last_signer: felt252) -> felt252;
    fn remove_signers(ref self: TContractState, signers_to_remove: Span<felt252>, last_signer: felt252);
    fn replace_signer(
        ref self: TContractState, signer_to_remove: felt252, signer_to_add: felt252, last_signer: felt252
    );
    fn load(self: @TContractState) -> (usize, felt252);
    fn is_signer_in_list(self: @TContractState, signer: felt252) -> bool;
    fn get_signers_len(self: @TContractState) -> usize;
    fn get_signers(self: @TContractState) -> Array<felt252>;
    fn is_signer_before(self: @TContractState, first_signer: felt252, second_signer: felt252) -> bool;
}
