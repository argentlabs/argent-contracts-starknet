#[account_contract]
mod ArgentAccount {
    use array::ArrayTrait;
    use array::SpanTrait;
    use box::BoxTrait;
    use ecdsa::check_ecdsa_signature;
    use traits::Into;
    use zeroable::Zeroable;

    use starknet::ContractAddress;
    use starknet::ContractAddressIntoFelt252;
    use starknet::get_block_info;
    use starknet::get_contract_address;
    use starknet::get_tx_info;
    use starknet::VALIDATED;

    use contracts::asserts::assert_only_self;
    use contracts::asserts::assert_no_self_call;
    use contracts::Escape;
    use contracts::Call;

    const NAME: felt252 = 'ArgentAccount';
    const VERSION: felt252 = '0.3.0-alpha.1';

    const ERC165_IERC165_INTERFACE_ID: felt252 = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt252 = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt252 = 0x3943f10f;
    const ERC1271_VALIDATED: felt252 = 0x1626ba7e;

    const ESCAPE_SECURITY_PERIOD: u64 = 604800_u64; // 7 * 24 * 60 * 60;  // 7 days

    const ESCAPE_TYPE_GUARDIAN: felt252 = 1;
    const ESCAPE_TYPE_SIGNER: felt252 = 2;

    // TODO: update selectors
    const CHANGE_SIGNER_SELECTOR: felt252 =
        174572128530328568741270994650351248940644050288235239638974755381225723145;
    const CHANGE_GUARDIAN_SELECTOR: felt252 =
        1296071702357547150019664216025682391016361613613945351022196390148584441374;
    const TRIGGER_ESCAPE_GUARDIAN_SELECTOR: felt252 =
        145954635736934016296422259475449005649670140213177066015821444644082814628;
    const TRIGGER_ESCAPE_SIGNER_SELECTOR: felt252 =
        440853473255486090032829492468113410146539319637824817002531798290796877036;
    const ESCAPE_GUARDIAN_SELECTOR: felt252 =
        510756951529079116816142749077704776910668567546043821008232923043034641617;
    const ESCAPE_SIGNER_SELECTOR: felt252 =
        1455116469465411075152303383382102930902943882042348163899277328605146981359;
    const CANCEL_ESCAPE_SELECTOR: felt252 =
        1387988583969094862956788899343599960070518480842441785602446058600435897039;
    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt252 =
        738349667340360233096752603318170676063569407717437256101137432051386874767;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Storage                                          //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    struct Storage {
        _signer: felt252,
        _guardian: felt252,
        _guardian_backup: felt252,
        _escape: Escape,
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Events                                           //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[event]
    fn AccountCreated(
        account: ContractAddress, key: felt252, guardian: felt252, new_guardian_backup: felt252
    ) {}

    #[event]
    fn TransactionExecuted(hash: felt252, response: Array<felt252>) {}

    #[event]
    fn EscapeSignerTriggered(active_at: u64) {}

    #[event]
    fn EscapeGuardianTriggered(active_at: u64) {}

    #[event]
    fn SignerEscaped(new_signer: felt252) {}

    #[event]
    fn GuardianEscaped(new_guardian: felt252) {}

    #[event]
    fn EscapeCanceled() {}

    #[event]
    fn SignerChanged(new_signer: felt252) {}

    #[event]
    fn GuardianChanged(new_guardian: felt252) {}

    #[event]
    fn GuardianBackupChanged(new_guardian: felt252) {}

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                     External functions                                     //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[external]
    fn __validate__(ref calls: Array::<Call>) -> felt252 {
        assert_initialized();

        let account_address = get_contract_address();

        if calls.len() == 1_usize {
            let call = calls.at(0_usize);
            if (*call.to).into() == account_address.into() {
                let tx_info = get_tx_info().unbox();
                let selector = *call.selector;
                if selector == ESCAPE_GUARDIAN_SELECTOR | selector == TRIGGER_ESCAPE_GUARDIAN_SELECTOR {
                    let is_valid = is_valid_signer_signature(
                        tx_info.transaction_hash, tx_info.signature
                    );
                    assert(is_valid, 'argent/invalid-signer-sig');
                    return VALIDATED;
                }
                if selector == ESCAPE_SIGNER_SELECTOR | selector == TRIGGER_ESCAPE_SIGNER_SELECTOR {
                    let is_valid = is_valid_guardian_signature(
                        tx_info.transaction_hash, tx_info.signature
                    );
                    assert(is_valid, 'argent/invalid-guardian-sig');
                    return VALIDATED;
                }
                assert(selector != EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
            }
        } else {
            // make sure no call is to the account
            assert_no_self_call(calls.span(), account_address);
        }

        assert_is_valid_signature();

        VALIDATED
    }

    #[external]
    fn __validate_declare__(class_hash: felt252) -> felt252 {
        assert_initialized();
        assert_is_valid_signature();
        VALIDATED
    }

    #[raw_input]
    #[external]
    fn __validate_deploy__(
        class_hash: felt252, contract_address_salt: felt252, public_key_: felt252
    ) -> felt252 {
        assert_initialized();
        assert_is_valid_signature();
        VALIDATED
    }

    #[external]
    fn initialize(new_signer: felt252, new_guardian: felt252, new_guardian_backup: felt252) {
        // check that we are not already initialized
        assert(_signer::read() == 0, 'argent/already-initialized');
        // check that the target signer is not zero
        assert(new_signer != 0, 'argent/null-signer');
        // There cannot be a guardian_backup when there is no guardian
        if new_guardian.is_zero() {
            assert(new_guardian_backup.is_zero(), 'argent/backup-should-be-null');
        }
        // initialize the account
        _signer::write(new_signer);
        _guardian::write(new_guardian);
        _guardian_backup::write(new_guardian_backup);
        AccountCreated(get_contract_address(), new_signer, new_guardian, new_guardian_backup);
    }

    #[external]
    fn change_signer(new_signer: felt252) {
        assert_only_self();
        assert(new_signer != 0, 'argent/null-signer');

        _signer::write(new_signer);
        SignerChanged(new_signer);
    }

    #[external]
    fn change_guardian(new_guardian: felt252) {
        assert_only_self();
        // There cannot be a guardian_backup when there is no guardian
        if new_guardian.is_zero() {
            assert(_guardian_backup::read().is_zero(), 'argent/backup-should-be-null');
        }

        _guardian::write(new_guardian);
        GuardianChanged(new_guardian);
    }

    #[external]
    fn change_guardian_backup(new_guardian_backup: felt252) {
        assert_only_self();
        assert_guardian_set();

        _guardian_backup::write(new_guardian_backup);
        GuardianBackupChanged(new_guardian_backup);
    }

    // TODO Shouldn't we specify who will be the new signer, and allow him to take ownership when time is over?
    // Ref https://twitter.com/bytes032/status/1628697044326969345
    // But then it means that if the escape isn't cancel, after timeout he can take the ownership at ANY time.
    #[external]
    fn trigger_escape_signer() {
        assert_only_self();
        assert_guardian_set();
        // TODO as this will only allow to delay the escape, is it relevant?
        // Can only escape signer by guardian, if there is no escape ongoing other or an escape ongoing but for of the type signer
        let current_escape = _escape::read();
        if current_escape.active_at != 0_u64 {
            assert(
                current_escape.escape_type == ESCAPE_TYPE_SIGNER, 'argent/cannot-override-escape'
            );
        }

        let active_at = get_block_info().unbox().block_timestamp + ESCAPE_SECURITY_PERIOD;
        // TODO Since timestamp is a u64, and escape type 1 small felt252, we can pack those two values and use 1 storage slot
        // TODO We could also inverse the way we store using a map and at ESCAPE_TYPE_SIGNER having the escape active_at of the signer and at ESCAPE_TYPE_GUARDIAN escape active_at
        // Since none of these two can be filled at the same time, it'll always use one and only one slot
        // Or we could simplify it by having the struct taking signer_active_at and guardian_active_at and no map
        _escape::write(Escape { active_at, escape_type: ESCAPE_TYPE_SIGNER });
        EscapeSignerTriggered(active_at);
    }

    #[external]
    #[inline(always)]
    fn trigger_escape_guardian() {
        assert_only_self();
        assert_guardian_set();

        let active_at = get_block_info().unbox().block_timestamp + ESCAPE_SECURITY_PERIOD;
        _escape::write(Escape { active_at, escape_type: ESCAPE_TYPE_GUARDIAN });
        EscapeGuardianTriggered(active_at);
    }

    #[external]
    fn escape_signer(new_signer: felt252) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_SIGNER);
        assert(new_signer != 0, 'argent/null-signer');
        // TODO Shouldn't we check new_signer != guardian?
        clear_escape();
        _signer::write(new_signer);
        SignerEscaped(new_signer);
    }

    #[external]
    fn escape_guardian(new_guardian: felt252) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_GUARDIAN);
        assert(new_guardian != 0, 'argent/null-guardian');

        clear_escape();
        _guardian::write(new_guardian);
        GuardianEscaped(new_guardian);
    }

    #[external]
    fn cancel_escape() {
        assert_only_self();
        assert(_escape::read().active_at != 0_u64, 'argent/no-active-escape');

        clear_escape();
        EscapeCanceled();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                       View functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[view]
    fn get_signer() -> felt252 {
        _signer::read()
    }

    #[view]
    fn get_guardian() -> felt252 {
        _guardian::read()
    }

    #[view]
    fn get_guardian_backup() -> felt252 {
        _guardian_backup::read()
    }

    #[view]
    fn get_escape() -> Escape {
        _escape::read()
    }

    #[view]
    fn get_version() -> felt252 {
        VERSION
    }

    #[view]
    fn get_name() -> felt252 {
        NAME
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt252) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }


    // ERC1271
    #[view]
    fn is_valid_signature(hash: felt252, signatures: Array<felt252>) -> felt252 {
        if is_valid_span_signature(hash, signatures.span()) {
            ERC1271_VALIDATED
        } else {
            0
        }
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                              External functions compatibility                              //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[external]
    fn changeSigner(new_signer: felt252) {
        change_signer(new_signer)
    }

    #[external]
    fn changeGuardian(new_guardian: felt252) {
        change_guardian(new_guardian)
    }

    #[external]
    fn changeGuardianBackup(new_guardian_backup: felt252) {
        change_guardian_backup(new_guardian_backup)
    }

    #[external]
    fn triggerEscapeSigner() {
        trigger_escape_signer()
    }

    #[external]
    fn triggerEscapeGuardian() {
        trigger_escape_guardian()
    }

    #[external]
    fn escapeSigner(new_signer: felt252) {
        escape_signer(new_signer)
    }

    #[external]
    fn escapeGuardian(new_guardian: felt252) {
        escape_guardian(new_guardian)
    }

    #[external]
    fn cancelEscape() {
        cancel_escape()
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                 View functions compatibility                               //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[view]
    fn getSigner() -> felt252 {
        get_signer()
    }

    #[view]
    fn getGuardian() -> felt252 {
        get_guardian()
    }

    #[view]
    fn getGuardianBackup() -> felt252 {
        get_guardian_backup()
    }

    #[view]
    fn getEscape() -> Escape {
        get_escape()
    }

    #[view]
    fn getVersion() -> felt252 {
        get_version()
    }

    #[view]
    fn getName() -> felt252 {
        get_name()
    }

    // ERC165
    #[view]
    fn supportsInterface(interface_id: felt252) -> bool {
        supports_interface(interface_id)
    }

    // ERC1271
    #[view]
    fn isValidSignature(hash: felt252, signatures: Array<felt252>) -> felt252 {
        is_valid_signature(hash, signatures)
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Internal                                          //
    ////////////////////////////////////////////////////////////////////////////////////////////////
    fn assert_is_valid_signature() {
        let tx_info = get_tx_info().unbox();
        let transaction_hash = tx_info.transaction_hash;
        let full_signature = tx_info.signature;

        let (signer_signature, guardian_signature) = split_signatures(full_signature);
        let is_valid = is_valid_signer_signature(transaction_hash, signer_signature);
        assert(is_valid, 'argent/invalid-signer-sig');
        if _guardian::read() != 0 {
            let is_valid = is_valid_guardian_signature(transaction_hash, guardian_signature);
            assert(is_valid, 'argent/invalid-guardian-sig');
        }
    }

    fn is_valid_span_signature(hash: felt252, signatures: Span<felt252>) -> bool {
        let (signer_signature, guardian_signature) = split_signatures(signatures);
        let is_valid = is_valid_signer_signature(hash, signer_signature);
        if !is_valid {
            return false;
        }
        if _guardian::read() == 0 {
            guardian_signature.is_empty()
        } else {
            is_valid_guardian_signature(hash, guardian_signature)
        }
    }

    fn is_valid_signer_signature(hash: felt252, signature: Span<felt252>) -> bool {
        if signature.len() != 2_usize {
            return false;
        }
        let signature_r = *signature.at(0_usize);
        let signature_s = *signature.at(1_usize);
        check_ecdsa_signature(hash, _signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(hash: felt252, signature: Span<felt252>) -> bool {
        if signature.len() != 2_usize {
            return false;
        }
        let signature_r = *signature.at(0_usize);
        let signature_s = *signature.at(1_usize);
        let is_valid = check_ecdsa_signature(hash, _guardian::read(), signature_r, signature_s);
        if is_valid {
            true
        } else {
            check_ecdsa_signature(hash, _guardian_backup::read(), signature_r, signature_s)
        }
    }

    fn split_signatures(full_signature: Span<felt252>) -> (Span::<felt252>, Span::<felt252>) {
        if full_signature.len() == 2_usize {
            return (full_signature, ArrayTrait::new().span());
        }
        assert(full_signature.len() == 4_usize, 'argent/invalid-signature-length');
        let mut signer_signature = ArrayTrait::new();
        signer_signature.append(*full_signature.at(0_usize));
        signer_signature.append(*full_signature.at(1_usize));
        let mut guardian_signature = ArrayTrait::new();
        guardian_signature.append(*full_signature.at(2_usize));
        guardian_signature.append(*full_signature.at(3_usize));
        (signer_signature.span(), guardian_signature.span())
    }

    #[inline(always)]
    fn clear_escape() {
        _escape::write(Escape { active_at: 0_u64, escape_type: 0 });
    }

    fn assert_can_escape_for_type(escape_type: felt252) {
        let current_escape = _escape::read();
        let block_timestamp = get_block_info().unbox().block_timestamp;

        assert(current_escape.active_at != 0_u64, 'argent/not-escaping');
        assert(current_escape.active_at <= block_timestamp, 'argent/inactive-escape');
        assert(current_escape.escape_type == escape_type, 'argent/invalid-escape-type');
    }

    #[inline(always)]
    fn assert_guardian_set() {
        assert(_guardian::read() != 0, 'argent/guardian-required');
    }

    #[inline(always)]
    fn assert_initialized() {
        assert(_signer::read() != 0, 'argent/uninitialized');
    }
}
