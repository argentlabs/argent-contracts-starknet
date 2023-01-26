#[contract]
mod ArgentAccount {
    use contracts::asserts;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

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
}
