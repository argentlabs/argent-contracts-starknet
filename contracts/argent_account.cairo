#[derive(Copy, Drop)]
struct CallArray {
    to: felt,
    selector: felt,
    data_offset: felt,
    data_len: felt,
}

#[contract]
mod ArgentAccount {
    use array::ArrayTrait;
    use contracts::asserts;
    use ecdsa::check_ecdsa_signature;
    use super::CallArray;

    impl ArrayCallArrayDrop of Drop::<Array::<CallArray>>;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    const CHANGE_SIGNER_SELECTOR: felt =
        174572128530328568741270994650351248940644050288235239638974755381225723145;
    const CHANGE_GUARDIAN_SELECTOR: felt =
        1296071702357547150019664216025682391016361613613945351022196390148584441374;
    const TRIGGER_ESCAPE_GUARDIAN_SELECTOR: felt =
        145954635736934016296422259475449005649670140213177066015821444644082814628;
    const TRIGGER_ESCAPE_SIGNER_SELECTOR: felt =
        440853473255486090032829492468113410146539319637824817002531798290796877036;
    const ESCAPE_GUARDIAN_SELECTOR: felt =
        510756951529079116816142749077704776910668567546043821008232923043034641617;
    const ESCAPE_SIGNER_SELECTOR: felt =
        1455116469465411075152303383382102930902943882042348163899277328605146981359;
    const CANCEL_ESCAPE_SELECTOR: felt =
        1387988583969094862956788899343599960070518480842441785602446058600435897039;
    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt =
        738349667340360233096752603318170676063569407717437256101137432051386874767;

    struct Storage {
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
    }
    
    #[event]
    fn AccountCreated(account: felt, key: felt, guardian: felt, guardian_backup: felt) {}

    #[event]
    fn TransactionExecuted(hash: felt, response: Array<felt>) {}

    // #[external] // ignored to avoid serde
    fn __validate__(ref call_array: Array::<CallArray>, ref calldata: Array::<felt>) {
        // make sure the account is initialized
        assert(signer::read() != 0, 'argent: account not initialized');

        let account_address = dummy_syscalls::get_contract_address();
        let transaction_hash = dummy_syscalls::get_transaction_hash();
        let mut signature = dummy_syscalls::get_signature();

        if call_array.len() == 1_usize {
            let call = call_array.at(0_usize);
            if call.to == account_address {
                if call.selector == ESCAPE_GUARDIAN_SELECTOR | call.selector == TRIGGER_ESCAPE_GUARDIAN_SELECTOR {
                    let is_valid = is_valid_signer_signature(ref signature, transaction_hash);
                    assert(is_valid, 'argent: signer signature invalid');
                    return ();
                }
                if call.selector == ESCAPE_SIGNER_SELECTOR | call.selector == TRIGGER_ESCAPE_SIGNER_SELECTOR {
                    let is_valid = is_valid_guardian_signature(ref signature, transaction_hash);
                    assert(is_valid, 'argent: guardian signature invalid');
                    return ();
                }
                assert(call.selector == EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent: forbidden call');
            }
        } else {
            // make sure no call is to the account
            asserts::assert_no_self_call(ref call_array, account_address, 0_usize);
        }
        let is_valid = is_valid_signer_signature(ref signature, transaction_hash);
        assert(is_valid, 'argent: signer signature invalid');
        let is_valid = is_valid_guardian_signature(ref signature, transaction_hash);
        assert(is_valid, 'argent: guardian signature invalid');
    }

    #[external]
    fn initialize(new_signer: felt, new_guardian: felt, new_guardian_backup: felt) {
        // check that we are not already initialized
        assert(signer::read() == 0, 'argent/already-initialized');
        // check that the target signer is not zero
        assert(new_signer != 0, 'argent/null-signer');
        // initialize the account
        signer::write(new_signer);
        guardian::write(new_guardian);
        guardian_backup::write(new_guardian_backup);
    // AccountCreated(starknet::get_contract_address(), new_signer, new_guardian, new_guardian_backup); Can't call yet
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
    fn is_valid_signature(hash: felt, signatures: Array<felt>) -> bool {
        let is_valid_signer = is_valid_signer_signature(hash, @signatures);
        let is_valid_guardian = is_valid_guardian_signature(hash, @signatures);
        is_valid_signer & is_valid_guardian
    }

    fn is_valid_signer_signature(hash: felt, signatures: @Array<felt>) -> bool {
        assert(signatures.len() >= 2_usize, 'argent/invalid-signature-length');
        let signature_r = *(signatures.at(0_usize));
        let signature_s = *(signatures.at(1_usize));
        check_ecdsa_signature(hash, signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(hash: felt, signatures: @Array<felt>) -> bool {
        let guardian_ = guardian::read();
        if guardian_ == 0 {
            assert(signatures.len() == 2_usize, 'argent/invalid-signature-length');
            return true;
        }
        assert(signatures.len() == 4_usize, 'argent/invalid-signature-length');
        let signature_r = *(signatures.at(2_usize));
        let signature_s = *(signatures.at(3_usize));
        let is_valid_guardian_signature = check_ecdsa_signature(
            hash, guardian_, signature_r, signature_s
        );
        if is_valid_guardian_signature {
            return true;
        }
        check_ecdsa_signature(hash, guardian_backup::read(), signature_r, signature_s)
    }
}
