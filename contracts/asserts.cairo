use contracts::dummy_syscalls;

const TRANSACTION_VERSION: felt = 1;
const QUERY_VERSION: felt = 340282366920938463463374607431768211457; // 2**128 + TRANSACTION_VERSION

fn assert_only_self() {
    let self = dummy_syscalls::get_contract_address();
    let caller_address = dummy_syscalls::get_caller_address();
    assert(self == caller_address, 'argent/only-self');
}

fn assert_non_reentrant(signer: felt) {
    let caller_address = dummy_syscalls::get_caller_address();
    assert(caller_address == 0, 'argent/no-reentrant-call');
}

fn assert_correct_tx_version(tx_version: felt) {
    assert(
        tx_version == TRANSACTION_VERSION ^ tx_version == QUERY_VERSION,
        'argent/invalid-tx-version'
    );
}
