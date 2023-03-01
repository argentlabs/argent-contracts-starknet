#[account_contract]
mod ArgentAccount {
    use traits::Into;
    use array::ArrayTrait;
    use ecdsa::check_ecdsa_signature;
    use starknet::get_contract_address;
    use starknet::get_tx_info;
    use starknet::ContractAddressIntoFelt;
    use contracts::asserts;
    use contracts::calls::Call;

    const VALIDATION_SUCCESS: felt = 'VALIDATED';
    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    // TODO: update selectors
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
    fn __validate__(ref calls: Array::<Call>) -> felt {
        // make sure the account is initialized
        assert(signer::read() != 0, 'argent/uninitialized');

        let account_address = get_contract_address();
        let tx_info = unbox(get_tx_info());
        let transaction_hash = tx_info.transaction_hash;
        let mut full_signature = tx_info.signature.snapshot;

        if calls.len() == 1_usize {
            let call = calls.at(0_usize);
            if (*call.to).into() == account_address.into() {
                let selector = *call.selector;
                if selector == ESCAPE_GUARDIAN_SELECTOR | selector == TRIGGER_ESCAPE_GUARDIAN_SELECTOR {
                    let is_valid = is_valid_signer_signature(transaction_hash, full_signature);
                    assert(is_valid, 'argent/invalid-signer-sig');
                    return VALIDATION_SUCCESS;
                }
                if selector == ESCAPE_SIGNER_SELECTOR | selector == TRIGGER_ESCAPE_SIGNER_SELECTOR {
                    let is_valid = is_valid_guardian_signature(transaction_hash, full_signature);
                    assert(is_valid, 'argent/invalid-guardian-sig');
                    return VALIDATION_SUCCESS;
                }
                assert(selector == EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
            }
        } else {
            // make sure no call is to the account
            asserts::assert_no_self_call(@calls, account_address);
        }

        let (signer_signature, guardian_signature) = split_signatures(full_signature);
        let is_valid = is_valid_signer_signature(transaction_hash, signer_signature);
        assert(is_valid, 'argent/invalid-signer-sig');
        let is_valid = is_valid_guardian_signature(transaction_hash, guardian_signature);
        assert(is_valid, 'argent/invalid-guardian-sig');

        VALIDATION_SUCCESS
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
    // AccountCreated(get_contract_address(), new_signer, new_guardian, new_guardian_backup); Can't call yet
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
        let (signer_signature, guardian_signature) = split_signatures(@signatures);
        let is_valid_signer = is_valid_signer_signature(hash, signer_signature);
        let is_valid_guardian = is_valid_guardian_signature(hash, guardian_signature);
        is_valid_signer & is_valid_guardian
    }

    fn is_valid_signer_signature(hash: felt, signature: @Array<felt>) -> bool {
        assert(signature.len() == 2_usize, 'argent/invalid-signature-length');
        let signature_r = *signature.at(0_usize);
        let signature_s = *signature.at(1_usize);
        check_ecdsa_signature(hash, signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(hash: felt, signature: @Array<felt>) -> bool {
        let guardian_ = guardian::read();
        if guardian_ == 0 {
            assert(signature.len() == 0_usize, 'argent/invalid-signature-length');
            return true;
        }
        assert(signature.len() == 2_usize, 'argent/invalid-signature-length');
        let signature_r = *signature.at(0_usize);
        let signature_s = *signature.at(1_usize);
        let is_valid = check_ecdsa_signature(hash, guardian_, signature_r, signature_s);
        if is_valid {
            return true;
        }
        check_ecdsa_signature(hash, guardian_backup::read(), signature_r, signature_s)
    }

    fn split_signatures(full_signature: @Array::<felt>) -> (@Array::<felt>, @Array::<felt>) {
        if full_signature.len() == 2_usize {
            return (full_signature, @ArrayTrait::new());
        }
        assert(full_signature.len() == 4_usize, 'argent/invalid-signature-length');
        let mut signer_signature = ArrayTrait::new();
        signer_signature.append(*full_signature.at(0_usize));
        signer_signature.append(*full_signature.at(1_usize));
        let mut guardian_signature = ArrayTrait::new();
        guardian_signature.append(*full_signature.at(2_usize));
        guardian_signature.append(*full_signature.at(3_usize));
        (@signer_signature, @guardian_signature)
    }
}
