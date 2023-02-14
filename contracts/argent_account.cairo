#[contract]
mod ArgentAccount {
    use array::ArrayTrait;
    use contracts::asserts;
    use contracts::dummy_syscalls;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    struct Storage {
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
    }


    #[event]
    fn AccountCreated(account: felt, key: felt, guardian: felt) {}

    #[event]
    fn TransactionExecuted(hash: felt, response: Array::<felt>) {}

    #[external]
    fn initialize(signer: felt, guardian: felt, guardian_backup: felt) {
        // check that we are not already initialized
        assert(signer::read() == 0, 'argent/already-initialized');
        // check that the target signer is not zero
        assert(signer != 0, 'argent/null-signer');
        // initialize the account
        signer::write(signer);
        guardian::write(guardian);
        guardian_backup::write(guardian_backup);
    // AccountCreated(dummy_syscalls::get_contract_address(), signer, guardian); Can't call yet
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

    #[external]
    fn change_signer(new_signer: felt) {
        // only called via execute
        asserts::assert_only_self();
        // check that the target signer is not zero
        assert(new_signer != 0, 'argent/null-signer');
        // update the signer
        signer::write(new_signer);
    }

    #[external]
    fn change_guardian(new_guardian: felt) {
        // only called via execute
        asserts::assert_only_self();
        // make sure guardian_backup = 0 when new_guardian = 0
        assert(new_guardian != 0 | guardian_backup::read() == 0, 'argent/guardian-backup-needed');
        // update the guardian
        guardian::write(new_guardian);
    }

    #[external]
    fn change_guardian_backup(new_guardian_backup: felt) {
        // only called via execute
        asserts::assert_only_self();
        assert(guardian::read() != 0, 'argent/guardian-required');
        // update the guardian backup
        guardian_backup::write(new_guardian_backup);
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    // ERC1271
    #[view]
    fn is_valid_signature(ref signatures: Array::<felt>, hash: felt) -> bool {
        let is_valid_signer = is_valid_signer_signature(ref signatures, hash);
        let is_valid_guardian = is_valid_guardian_signature(ref signatures, hash);
        is_valid_signer & is_valid_guardian
    }

    fn is_valid_signer_signature(ref signatures: Array::<felt>, hash: felt) -> bool {
        assert(signatures.len() >= 2_usize, 'argent/invalid-signature-length');
        let signature_r = signatures.at(0_usize);
        let signature_s = signatures.at(1_usize);
        ecdsa::check_ecdsa_signature(hash, signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(ref signatures: Array::<felt>, hash: felt) -> bool {
        let guardian_ = guardian::read();
        if guardian_ == 0 {
            assert(signatures.len() == 2_usize, 'argent/invalid-signature-length');
            return true;
        }
        assert(signatures.len() == 4_usize, 'argent/invalid-signature-length');
        let signature_r = signatures.at(2_usize);
        let signature_s = signatures.at(3_usize);
        let is_valid_guardian_signature = ecdsa::check_ecdsa_signature(
            hash, guardian_, signature_r, signature_s
        );
        if is_valid_guardian_signature {
            return true;
        }
        ecdsa::check_ecdsa_signature(hash, guardian_backup::read(), signature_r, signature_s)
    }
}
