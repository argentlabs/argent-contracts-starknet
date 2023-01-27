use contracts::dummy_syscalls;

fn assert_only_self() {
    let self = dummy_syscalls::get_contract_address();
    let caller_address = dummy_syscalls::get_caller_address();
    assert(self == caller_address, 'argent: only self');
}

fn assert_non_reentrant(signer: felt) {
    let caller_address = dummy_syscalls::get_caller_address();
    assert(caller_address == 0, 'argent: argent: no reentrant call');
}


fn assert_initialized(signer: felt) {
    // read signer from contract storage 
    // let signer = signer::read();
    assert(signer != 0, 'argent: account not initialized');
}

fn assert_correct_tx_version(tx_version: felt) {
    let correct_tx_version = 1;
    let query_version = 2;
    assert(tx_version == correct_tx_version ^ tx_version == query_version, 'argent: invalid tx version');
}

fn assert_guardian_set(guardian: felt) {
    // read guardian from contract storage 
    // let guardian= guardian::read();
    assert(guardian != 0, 'argent: guardian required');
}
