#[contract]
mod ArgentAccount {
    use array::ArrayTrait;
    use contracts::asserts::assert_only_self;
    use serde::Serde;
    use zeroable::Zeroable;
    use ecdsa::check_ecdsa_signature;
    use option::OptionTrait;
    use starknet::StorageAccess;
    use starknet::get_block_timestamp;
    use traits::TryInto;
    use traits::Into;
    use integer::FeltTryIntoU64;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    const ESCAPE_SECURITY_PERIOD: u64 = 604800_u64; // 7 * 24 * 60 * 60;  // 7 days

    const ESCAPE_TYPE_GUARDIAN: felt = 1;
    const ESCAPE_TYPE_SIGNER: felt = 2;

    #[derive(Copy)]
    struct Escape {
        active_at: u64,
        escape_type: felt, // TODO Change to enum? ==> Can't do ATM
    }

    impl StorageAccessEscape of StorageAccess::<Escape> {
        fn read(
            address_domain: felt, base: starknet::StorageBaseAddress
        ) -> starknet::SyscallResult::<Escape> {
            Result::Ok(
                Escape {
                    active_at: (StorageAccess::<felt>::read(
                        address_domain, base
                    )?).try_into().unwrap(),
                    escape_type: starknet::storage_read_syscall(
                        address_domain, starknet::storage_address_from_base_and_offset(base, 1_u8)
                    )?,
                }
            )
        }
        fn write(
            address_domain: felt, base: starknet::StorageBaseAddress, value: Escape
        ) -> starknet::SyscallResult::<()> {
            StorageAccess::write(address_domain, base, value.active_at.into())?;
            starknet::storage_write_syscall(
                address_domain,
                starknet::storage_address_from_base_and_offset(base, 1_u8),
                value.escape_type
            )
        }
    }

    impl EscapeSerde of Serde::<Escape> {
        fn serialize(ref serialized: Array::<felt>, input: Escape) {
            Serde::<u64>::serialize(ref serialized, input.active_at);
            Serde::serialize(ref serialized, input.escape_type);
        }
        fn deserialize(ref serialized: Array::<felt>) -> Option::<Escape> {
            Option::Some(
                Escape {
                    active_at: Serde::<u64>::deserialize(ref serialized)?,
                    escape_type: Serde::deserialize(ref serialized)?,
                }
            )
        }
    }


    /////////////////////
    // STORAGE
    /////////////////////

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
    fn AccountCreated(account: felt, key: felt, guardian: felt, guardian_backup: felt) {}

    #[event]
    fn TransactionExecuted(hash: felt, response: Array::<felt>) {}

    #[event]
    fn escape_signer_triggered(active_at: felt) {}

    #[event]
    fn signer_escaped(new_signer: felt) {}

    #[event]
    fn escape_guardian_triggered(active_at: felt) {}

    #[event]
    fn guardian_escaped(new_guardian: felt) {}

    #[event]
    fn escape_canceled() {}


    /////////////////////
    // EXTERNAL FUNCTIONS
    /////////////////////

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
        assert_only_self();
        // check that the target signer is not zero
        assert(new_signer != 0, 'argent/null-signer');
        // update the signer
        signer::write(new_signer);
    }

    #[external]
    fn change_guardian(new_guardian: felt) {
        // only called via execute
        assert_only_self();
        // make sure guardian_backup = 0 when new_guardian = 0
        assert(
            !new_guardian.is_zero() | guardian_backup::read().is_zero(),
            'argent/guardian-backup-needed'
        );
        // update the guardian
        guardian::write(new_guardian);
    }


    #[external]
    fn trigger_escape_signer() {
        // only called via execute
        assert_only_self();
        // no escape when the guardian is not set
        assert_guardian_set();

        // no escape if there is a guardian escape triggered by the signer in progress
        let current_escape = escape::read();
        assert(current_escape.active_at.into().is_zero(), 'argent/cannot-override-escape');
        // TODO Doubt correct
        assert(current_escape.escape_type != ESCAPE_TYPE_SIGNER, 'argent/cannot-override-escape');

        // store new escape
        let block_timestamp = get_block_timestamp();
        escape::write(
            Escape {
                active_at: block_timestamp + ESCAPE_SECURITY_PERIOD, escape_type: ESCAPE_TYPE_SIGNER
            }
        );
    // escape_signer_triggered.emit(block_timestamp + ESCAPE_SECURITY_PERIOD);
    }

    #[external]
    fn trigger_escape_guardian() {
        // only called via execute
        assert_only_self();
        // no escape when the guardian is not set
        assert_guardian_set();

        // TODO Should we check for overrides escape like in trigger_escape_signer
        // store new escape
        let block_timestamp = get_block_timestamp();
        escape::write(
            Escape {
                active_at: block_timestamp + ESCAPE_SECURITY_PERIOD,
                escape_type: ESCAPE_TYPE_GUARDIAN
            }
        );
    // escape_guardian_triggered.emit(block_timestamp + ESCAPE_SECURITY_PERIOD);
    }

    #[external]
    fn escape_signer(new_signer: felt) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_SIGNER);
        // TODO != 0 should be replaced by is_non_zero() when they merge it
        assert(new_signer != 0, 'argent/new-signer-zero');
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
        assert(new_guardian != 0, 'argent/new-guardian-zero');

        clear_escape();
        guardian::write(new_guardian);
    // guardian_escaped(new_guardian);

    }


    #[external]
    fn cancel_escape() {
        assert_only_self();
        // validate there is an active escape
        assert(escape::read().active_at != 0_u64, 'argent/no-active-escape');
        // clear escape
        clear_escape();
    // escape_canceled();
    }

    #[external]
    fn change_guardian_backup(new_guardian_backup: felt) {
        // only called via execute
        assert_only_self();
        assert(guardian::read() != 0, 'argent/guardian-required');
        // update the guardian backup
        guardian_backup::write(new_guardian_backup);
    }

    /////////////////////
    // VIEW FUNCTIONS
    /////////////////////

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
    fn is_valid_signature(hash: felt, signatures: Array::<felt>) -> bool {
        let is_valid_signer = is_valid_signer_signature(hash, @signatures);
        let is_valid_guardian = is_valid_guardian_signature(hash, @signatures);
        is_valid_signer & is_valid_guardian
    }

    fn is_valid_signer_signature(hash: felt, signatures: @Array::<felt>) -> bool {
        assert(signatures.len() >= 2_usize, 'argent/invalid-signature-length');
        let signature_r = *(signatures.at(0_usize));
        let signature_s = *(signatures.at(1_usize));
        check_ecdsa_signature(hash, signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(hash: felt, signatures: @Array::<felt>) -> bool {
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
    /////////////////////
    // UTILS
    /////////////////////

    #[inline(always)]
    fn clear_escape() {
        escape::write(Escape { active_at: 0_u64, escape_type: 0 });
    }

    fn assert_can_escape_for_type(escape_type: felt) {
        let current_escape = escape::read();
        let block_timestamp = get_block_timestamp();

        assert(current_escape.active_at != 0_u64, 'argent/not-escaping');
        assert(current_escape.active_at <= block_timestamp, 'argent/escape-not-active');
        assert(current_escape.escape_type == escape_type, 'argent/escape-type-invalid');
    }

    fn assert_guardian_set() {
        assert(!(guardian::read()).is_zero(), 'argent/guardian-required');
    }
}
