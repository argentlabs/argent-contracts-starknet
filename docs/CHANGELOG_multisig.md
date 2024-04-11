# Argent Multisig Changelog

# Version 0.2.0
- **Multiple signer types:** See [Signers and signatures](signers_and_signatures.md)
- **Multisig recovery:** See [Multisig Recovery](multisig_recovery.md)
- **Outside Execution V2:** See [Outside Execution](outside_execution.md)
- **Upgrade changes:** You cannot downgrade from 0.2.0 to an older version
- **Better gas estimates:** 

    Even if you don't have access to all the signer private keys, you can estimate a transaction including the validation part. By using an estimate tx version (0x100000000000000000000000000000000 + the actual transaction version). When doing so, the signature verification will still pass even if the signatures are not correct. Note that you still need to provide the signature in a valid format

### More details about the changes

- The following method had a signature change following the changes to allow Multiple signers
    ```
    fn constructor(new_threshold: usize, signers: Array<Signer>)
    fn add_signers(new_threshold: usize, signers_to_add: Array<Signer>);
    fn remove_signers(new_threshold: usize, signers_to_remove: Array<Signer>);
    fn replace_signer(signer_to_remove: Signer, signer_to_add: Signer);
    fn is_valid_signer_signature(hash: felt252, signer_signature: SignerSignature) -> bool;
    ```
- `get_signers() -> Array<felt252>` was replaced by `fn get_signer_guids() -> Array<felt252>` to make clear it returns the guids instead of the pub keys
- `is_signer(signer: felt252) -> bool` was replaced by ` is_signer_guid(signer_guid: felt252) -> bool`

- Some events were renamed and emit GUIDs instead of starknetpubkeys.
    `OwnerAdded` was replaced by
    ```
    struct OwnerAddedGuid {
        #[key]
        new_owner_guid: felt252,
    }
    ```

    And `OwnerRemoved` replaced by
    ```
    struct OwnerRemovedGuid {
        #[key]
        removed_owner_guid: felt252,
    }
    ```

# Version 0.1.1
Support for Transactions V3 that allows paying the transaction fees in STRK token

# Version 0.1.0
First release 