const ERC1271_VALIDATED: felt252 = 0x1626ba7e;

#[starknet::interface]
trait IErc1271<TContractState> {
    fn is_valid_signature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}
