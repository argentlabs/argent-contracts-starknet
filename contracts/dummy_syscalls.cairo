use starknet::ContractAddress;
use starknet::contract_address_const;

fn get_contract_address() -> ContractAddress {
    contract_address_const::<69>()
}

fn get_caller_address() -> ContractAddress {
    contract_address_const::<69>()
}

fn get_block_number() -> u64 {
    1_u64
}

fn get_tx_info() {}

fn call_contract(to: felt, selector: felt, calldata: @Array::<felt>) -> Array::<felt> {
    array_new()
}
