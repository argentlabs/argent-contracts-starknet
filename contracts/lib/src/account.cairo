use starknet::account::Call;

const ERC165_ACCOUNT_INTERFACE_ID: felt252 =
    0x32a450d0828523e159d5faa1f8bc3c94c05c819aeb09ec5527cd8795b5b5067;
const ERC165_ACCOUNT_INTERFACE_ID_OLD_1: felt252 = 0xa66bd575;
const ERC165_ACCOUNT_INTERFACE_ID_OLD_2: felt252 = 0x3943f10f;

const ERC1271_VALIDATED: felt252 = 0x1626ba7e;

// InterfaceID: 0x32a450d0828523e159d5faa1f8bc3c94c05c819aeb09ec5527cd8795b5b5067
trait IAccount<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn is_valid_signature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> bool;
}
