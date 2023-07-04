use starknet::account::Call;

const ERC165_ACCOUNT_INTERFACE_ID: felt252 =
    0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd;
const ERC165_ACCOUNT_INTERFACE_ID_OLD_1: felt252 = 0xa66bd575;
const ERC165_ACCOUNT_INTERFACE_ID_OLD_2: felt252 = 0x3943f10f;

const ERC1271_VALIDATED: felt252 = 0x1626ba7e;

// InterfaceID: 0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd
trait IAccount<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn is_valid_signature(
        self: @TContractState, hash: felt252, signature: Array<felt252>
    ) -> felt252;
}
