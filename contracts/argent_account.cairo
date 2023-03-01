#[account_contract]
mod ArgentAccount {
    use traits::Into;
    use array::ArrayTrait;
    use zeroable::Zeroable;
    use box::unbox;

    use starknet::get_contract_address;
    use starknet::get_tx_info;
    use starknet::ContractAddressIntoFelt;
    use starknet::get_block_info;
    use ecdsa::check_ecdsa_signature;

    use contracts::asserts::assert_only_self;
    use contracts::asserts::assert_no_self_call;
    use contracts::StorageAccessEscape;
    use contracts::EscapeSerde;
    use contracts::calls::Call;

    const VALIDATION_SUCCESS: felt = 'VALIDATED';
    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    const ESCAPE_SECURITY_PERIOD: u64 = 604800_u64; // 7 * 24 * 60 * 60;  // 7 days

    const ESCAPE_TYPE_GUARDIAN: felt = 1;
    const ESCAPE_TYPE_SIGNER: felt = 2;

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


    /////////////////////
    // STORAGE
    /////////////////////

    #[derive(Copy)]
    struct Escape {
        active_at: u64,
        escape_type: felt, // TODO Change to enum? ==> Can't do ATM because would have to impl partialEq, update storage, etc etc
    }

    struct Storage {
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
        escape: Escape,
    }

    /////////////////////
    // EVENTS
    /////////////////////

    #[event]
    fn account_created(account: felt, key: felt, guardian: felt, guardian_backup: felt) {}

    #[event]
    fn transaction_executed(hash: felt, response: Array<felt>) {}

    #[event]
    fn escape_signer_triggered(active_at: u64) {}


    #[event]
    fn escape_guardian_triggered(active_at: felt) {}

    #[event]
    fn signer_escaped(new_signer: felt) {}

    #[event]
    fn guardian_escaped(new_guardian: felt) {}

    #[event]
    fn escape_canceled() {}

    /////////////////////
    // EXTERNAL FUNCTIONS
    /////////////////////
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
            assert_no_self_call(@calls, account_address);
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
    // account_created(starknet::get_contract_address(), new_signer, new_guardian, new_guardian_backup);
    }

    #[external]
    fn change_signer(new_signer: felt) {
        assert_only_self();
        assert(new_signer != 0, 'argent/null-signer');
        // update the signer
        signer::write(new_signer);
    }

    #[external]
    fn change_guardian(new_guardian: felt) {
        assert_only_self();
        if new_guardian.is_zero() {
            assert(guardian_backup::read().is_zero(), 'argent/guardian-backup-required');
        }

        // update the guardian
        guardian::write(new_guardian);
    }

    #[external]
    fn change_guardian_backup(new_guardian_backup: felt) {
        assert_only_self();
        assert_guardian_set();

        guardian_backup::write(new_guardian_backup);
    }

    // TODO Shouldn't we specify who will be the new signer, and allow him to take ownership when time is over?
    // Ref https://twitter.com/bytes032/status/1628697044326969345
    // But then it means that if the escape isn't cancel, after timeout he can take the ownership at ANY time.
    #[external]
    fn trigger_escape_signer() {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_signer();

        // store new escape
        let active_at = unbox(get_block_info()).block_timestamp + ESCAPE_SECURITY_PERIOD;
        // TODO Since timestamp is a u64, and escape type 1 small felt, we can pack those two values and use 1 storage slot
        escape::write(Escape { active_at, escape_type: ESCAPE_TYPE_SIGNER });
    // escape_signer_triggered(active_at);
    }

    #[external]
    fn trigger_escape_guardian() {
        assert_only_self();
        assert_guardian_set();

        // store new escape
        let active_at = unbox(get_block_info()).block_timestamp + ESCAPE_SECURITY_PERIOD;
        escape::write(Escape { active_at, escape_type: ESCAPE_TYPE_GUARDIAN });
    // escape_guardian_triggered(active_at);
    }

    #[external]
    fn escape_signer(new_signer: felt) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_SIGNER);
        assert(new_signer != 0, 'argent/null-signer');

        // TODO Shouldn't we check new_signer != guardian?
        clear_escape();
        signer::write(new_signer);
    // signer_escaped(new_signer);

    }

    #[external]
    fn escape_guardian(new_guardian: felt) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_GUARDIAN);
        assert(new_guardian != 0, 'argent/null-guardian');

        clear_escape();
        guardian::write(new_guardian);
    // guardian_escaped(new_guardian);

    }


    #[external]
    fn cancel_escape() {
        assert_only_self();
        assert(escape::read().active_at != 0_u64, 'argent/no-active-escape');

        clear_escape();
    // escape_canceled();
    }

    /////////////////////
    // VIEW FUNCTIONS
    /////////////////////

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

    #[view]
    fn get_escape() -> Escape {
        escape::read()
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

    /////////////////////
    // UTILS
    /////////////////////

    #[inline(always)]
    fn clear_escape() {
        escape::write(Escape { active_at: 0_u64, escape_type: 0 });
    }

    fn assert_can_escape_for_type(escape_type: felt) {
        let current_escape = escape::read();
        // TODO Hopefuly there will be a way to directly get the block timestamp without having to do this magic (will do a PR in their repo RN) 
        let block_timestamp = unbox(get_block_info()).block_timestamp;

        assert(current_escape.active_at != 0_u64, 'argent/not-escaping');
        assert(current_escape.active_at <= block_timestamp, 'argent/inactive-escape');
        assert(current_escape.escape_type == escape_type, 'argent/invalid-escape-type');
    }

    #[inline(always)]
    fn assert_guardian_set() {
        assert(guardian::read() != 0, 'argent/guardian-required');
    }

    #[inline(always)]
    fn assert_can_escape_signer() {
        let current_escape = escape::read();
        if current_escape.active_at != 0_u64 {
            assert(
                current_escape.escape_type == ESCAPE_TYPE_SIGNER, 'argent/cannot-override-escape'
            );
        }
    }
}
