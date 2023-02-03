use array::ArrayTrait;

fn get_contract_address() -> felt {
    69
}

fn get_caller_address() -> felt {
    69
}

fn get_block_number() -> felt {
    1
}

fn get_transaction_hash() -> felt {
    420
}

fn get_signature() -> Array::<felt> {
    let mut signature = ArrayTrait::new();
    signature.append(1);
    signature.append(2);
    signature
}

fn get_tx_info() {}

fn call_contract(to: felt, selector: felt, calldata: Array::<felt>) -> Array::<felt> {
    array_new()
}
