#[contract]
mod ArgentAccount {
    use contracts::dummy_syscalls;
    use contracts::asserts;
    
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;
    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;

    struct Storage { 
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
    }

    #[external]
    fn initialize(signer: felt, guardian: felt, guardian_backup: felt) {
        // check that we are not already initialized
        assert(signer::read() == 0, 'argent: already initialized');
        // check that the target signer is not zero
        assert(signer != 0, 'argent: signer cannot be null');
        // initialize the account
        signer::write(signer);
        guardian::write(guardian);
        guardian_backup::write(guardian_backup);
    }

    #[view]
    fn get_signer() -> felt {
        signer::read()
    }

    #[view]
    fn get_guardian() -> felt {
        guardian::read()
    }

    #[view]
    fn get_guardian_backup() -> felt {
        guardian_backup::read()
    }

    // ERC165
    #[view]
    fn supportsInterface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | 
        interface_id == ERC165_ACCOUNT_INTERFACE_ID |
        interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    #[view]
    fn get_contract_address_test() -> felt {
        dummy_syscalls::get_contract_address() 
    }

    fn assert_only_self_test() -> felt {
        let a = 1;
        asserts::assert_only_self();
        a
    }

    fn assert_guardian_set_test() -> felt {
        let a = 1;
        let guardian = guardian::read();
        asserts::assert_guardian_set(guardian);
        a
    }

    fn assert_correct_tx_version_test(tx_version: felt) -> felt {
        let a = 1;
        asserts::assert_correct_tx_version(tx_version);
        1
    }


}