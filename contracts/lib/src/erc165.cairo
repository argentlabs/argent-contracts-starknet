const ERC165_IERC165_INTERFACE_ID: felt252 = 0x01ffc9a7;

const ERC165_ACCOUNT_INTERFACE_ID: felt252 =
    0x396002e72b10861a183bd73bd37e3a27a36b685f488f45c2d3e664d0009e51c;
const ERC165_ACCOUNT_INTERFACE_ID_OLD_1: felt252 = 0xa66bd575;
const ERC165_ACCOUNT_INTERFACE_ID_OLD_2: felt252 = 0x3943f10f;

#[starknet::interface]
trait IErc165<TContractState> {
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
}
