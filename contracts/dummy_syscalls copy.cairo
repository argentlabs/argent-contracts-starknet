use array::ArrayTrait;

#[derive(Drop)]
struct TxInfo {
    version: felt,
    account_contract_address: felt,
    max_fee: felt,
    signature: Array::<felt>,
    transaction_hash: felt,
    chain_id: felt,
    nonce: felt,
}

fn get_contract_address() -> felt {
    69
}

fn get_caller_address() -> felt {
    69
}

fn get_block_number() -> felt {
    1
}

fn get_tx_info() -> TxInfo {
    let mut signature = ArrayTrait::new();
    signature.append(1);
    TxInfo {
        version: 1,
        account_contract_address: 1,
        max_fee: 1,
        signature,
        transaction_hash: 69,
        chain_id: 1,
        nonce: 1,
    }
}

fn call_contract(to: felt, selector: felt, calldata: Array::<felt>) -> Array::<felt> {
    array_new()
}
