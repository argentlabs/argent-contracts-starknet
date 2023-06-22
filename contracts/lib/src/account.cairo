use starknet::account::Call;

const ERC1271_VALIDATED: felt252 = 0x1626ba7e;

trait IAccount<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn is_valid_signature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}
