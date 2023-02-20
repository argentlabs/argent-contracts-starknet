#[contract]
mod ArgentMultisigAccount {

    struct Storage {
    threshold: felt,
    }

    // @dev Set the initial parameters for the multisig. It's mandatory to call this methods to secure the account.
    // It's recommended to call this method in the same transaction that deploys the account to make sure it's always initialized
    #[external]
    fn initialize(
        threshold: felt,  signers: Array::<felt>
    ) {

        let current_threshold = storage_threshold::read();
        assert(current_threshold == 0, 'argent/already-initialized');

        // assert_valid_threshold_and_signers_count(threshold=threshold, signers_len=signers_len);

        // SignerStorage.add_signers(signers_len, signers, last_signer=0);
        // storage_threshold.write(threshold);    

        // configuration_updated.emit(
        //     new_threshold=threshold,
        //     new_signers_count=signers_len,
        //     added_signers_len=signers_len,
        //     added_signers=signers,
        //     removed_signers_len=0,
        //     removed_signers=cast(0, felt*),
        // );

    }

}