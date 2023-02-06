#[contract]
mod ArgentAccount {
    use array::ArrayTrait;
    use contracts::asserts;
    use contracts::dummy_syscalls;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    const ESCAPE_SECURITY_PERIOD: felt = 604800; // 7 days
    const ESCAPE_TYPE_GUARDIAN: felt = 1;
    const ESCAPE_TYPE_SIGNER: felt = 2;


    struct Storage {
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
        escape_active_at: felt,
        escape_type: felt,
    }

    #[event]
    fn AccountCreated(account: felt, key: felt, guardian: felt) {}

    #[event]
    fn TransactionExecuted(hash: felt, response: Array::<felt>) {}

    #[event]
    fn EscapeSignerTriggered(active_at: felt) {}

    #[event]
    fn SignerEscaped(new_signer: felt) {}

    #[event]
    fn EscapeCanceled() {}

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

    #[view]
    fn get_escape_active_at() -> felt {
        escape_active_at::read()
    }

    #[view]
    fn get_escape_type() -> felt {
        escape_type::read()
    }

    #[external]
    fn changeSigner(new_signer: felt) {
        // only called via execute
        asserts::assert_only_self();
        // check that the target signer is not zero
        assert(new_signer != 0, 'argent: signer cannot be null');
        // update the signer
        signer::write(new_signer);
    }

    #[external]
    fn changeGuardian(new_guardian: felt) {
        // only called via execute
        asserts::assert_only_self();
        // make sure guardian_backup = 0 when new_guardian = 0
        if new_guardian == 0 {
            assert(guardian_backup::read() == 0, 'argent: new guardian invalid');
        }
        // update the guardian
        guardian::write(new_guardian);
    }

    #[external]
    fn changeGuardianBackup(new_guardian_backup: felt) {
        // only called via execute
        asserts::assert_only_self();
        assert(guardian::read() != 0, 'argent: guardian required');
        // update the guardian backup
        guardian_backup::write(new_guardian_backup);
    }

    // ERC165
    #[view]
    fn supportsInterface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    // ERC1271
    #[view]
    fn isValidSignature(ref signatures: Array::<felt>, hash: felt) -> bool {
        let is_valid_signer = is_valid_signer_signature(ref signatures, hash);
        let is_valid_guardian = is_valid_guardian_signature(ref signatures, hash);
        is_valid_signer & is_valid_guardian
    }

    fn is_valid_signer_signature(ref signatures: Array::<felt>, hash: felt) -> bool {
        assert(signatures.len() >= 2_usize, 'argent: signature format invalid');
        let signature_r = signatures.at(0_usize);
        let signature_s = signatures.at(1_usize);
        ecdsa::check_ecdsa_signature(hash, signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(ref signatures: Array::<felt>, hash: felt) -> bool {
        let guardian_ = guardian::read();
        if guardian_ == 0 {
            assert(signatures.len() == 2_usize, 'argent: signature format invalid');
            return true;
        }
        assert(signatures.len() == 4_usize, 'argent: signature format invalid');
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

    #[external]
    fn triggerEscapeSigner() {
        // only called via execute
        asserts::assert_only_self();

        // no escape when the guardian is not set
        assert(guardian::read() != 0, 'argent: guardian required');

        // no escape if there is a guardian escape triggered by the signer in progress
        let escape_timestamp = escape_active_at::read();
        if escape_timestamp != 0 {
            let escape_type = escape_type::read();
            assert(escape_type == ESCAPE_TYPE_SIGNER, 'argent: cannot override escape');
        };

        // store new escape
        let block_timestamp = dummy_syscalls::get_block_timestamp();
        let new_escape_activation = block_timestamp + ESCAPE_SECURITY_PERIOD;
        escape_active_at::write(new_escape_activation);
        escape_type::write(ESCAPE_TYPE_SIGNER);
    // EscapeSignerTriggered(new_escape_activation); Can't call yet
    }

    #[external]
    fn cancelEscape() {
        // only called via execute
        asserts::assert_only_self();

        // validate there is an active escape
        let escape_timestamp = escape_active_at::read();
        assert(escape_timestamp != 0, 'argent: no active escape"');

        // clear escape
        escape_active_at::write(0);
        escape_type::write(0);
    // EscapeCanceled(); Can't call yet
    }

    #[external]
    fn escapeSigner(new_signer: felt, block_timestamp: felt) {
        // only called via execute
        asserts::assert_only_self();
        // no escape when the guardian is not set
        assert(guardian::read() != 0, 'argent: guardian required');

        let escape_timestamp = escape_active_at::read();
        // TODO: add syscall to block timestamp, once block timestamp can be changed 
        // currently passed in as a param

        assert(escape_timestamp != 0, 'argent: not escaping');
        assert(escape_timestamp < block_timestamp, 'argent: escape not active');

        let escape_type = escape_type::read();
        assert(escape_type == ESCAPE_TYPE_SIGNER, 'argent: escape type invalid');

        // clear escape
        escape_active_at::write(0);
        escape_type::write(0);

        // change signer
        assert(new_signer != 0, 'argent: signer cannot be null');
        signer::write(new_signer);
    // SignerEscaped(new_signer);
    }
}
