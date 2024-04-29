# Argent Account Changelog

# Version 0.4.0

- **Multiple signer types:** See [Signers and signatures](signers_and_signatures.md)
- **Sessions:** See [Sessions](sessions.md)
- **Outside Execution V2:** See [Outside Execution](outside_execution.md)
- **Configurable escape security period**
  Starting on this version, users can change the security period used for escapes. It will still default to 1 week but it's now possible to change. Changing the security window will also affect the expiration time. For instance changing the security period to 48 hours means that, you need to wait 48h before the update is ready to be completed, and also, it needs to be completed in the following 48h or it will expire
- **Better gas estimates:**
  Even if you don't have access to all the signer private keys, you can estimate a transaction including the validation part. By using an estimate tx version (0x100000000000000000000000000000000 + the actual transaction version). When doing so, the signature verification will still pass even if the signatures are not correct. Note that you still need to provide the signature in a valid format

- **Gas griefing mitigation changes:**
  Before this version the account would only pay for a fixed number of escape transactions (where only one of the two signatures are needed). To complete an escape after the limit was reached, it was needed to submit a transaction using outside execution

  Starting in this version of the account, the mechanism was replaced with a limit on the frequency of the escape transactions

- **Upgrade changes:** you cannot downgrade from 0.4.0 to an older version

### More details about the changes

- `get_owner()`, `get_guardian()` and `get_guardian_backup()`: Will return the public key if the requested role is Starknet, Eip191 or Secp256k1 but panic otherwise

- Many functions had a signature change to include the `Signer`

  ```
  fn constructor(owner: Signer, guardian: Option<Signer>)
  fn change_owner(signer_signature: SignerSignature)
  fn change_guardian(new_guardian: Option<Signer>)
  fn change_guardian_backup(new_guardian_backup: Option<Signer>)
  fn trigger_escape_owner(new_owner: Signer)
  fn trigger_escape_guardian(new_guardian: Option<Signer>)
  fn get_escape() -> Escape
  fn get_escape_and_status() -> (Escape, EscapeStatus)
  ```

- Different signature for the `change_owner` function
  Before, the signature included the old owner pubkey, but it has been replaced by the old guid
  The hash to sign is now the pedersen hash of the array: [change_owner_selector, chain_id, account_address, old_owner_guid]

- Escape struct also changed, creating some changes to the escape functions

  ```
  fn get_escape() -> Escape
  fn get_escape_and_status() -> (Escape, EscapeStatus)

  struct Escape {
      ready_at: u64,
      escape_type: EscapeType,
      new_signer: Option<SignerStorageValue>,
  }
  ```

- Events were renamed and emit GUIDs instead of starknetpubkeys.
  For instance `AccountCreated` will become

  ```
  struct AccountCreatedGuid {
      #[key]
      owner_guid: felt252,
      guardian_guid: felt252
  }
  ```

  The same change applies to:

  ```
  OwnerChangedGuid
  GuardianChangedGuid
  GuardianBackupChangedGuid
  EscapeOwnerTriggeredGuid
  EscapeGuardianTriggeredGuid
  OwnerEscapedGuid
  GuardianEscapedGuid
  ```

  To keep backwards compatibility issues, the account will still emit when the following events with when the signers in the even are starknet keys

  ```
  OwnerChanged
  GuardianChanged
  GuardianBackupChanged
  ```

- Signatures now have a new format but the old format is still allowed. Unless trying to use a guardian backup.

- `get_guardian_escape_attempts` and `get_owner_escape_attempts` were removed with the new gas griefing mitigation

- new functions `set_escape_security_period` and get_escape_security_period, to change the security period used for escapes

- new functions related to new signer types: `get_owner_guid`, `get_owner_type`, `is_guardian`, `get_guardian_guid`, `get_guardian_type`, `get_guardian_backup_guid`, `get_guardian_backup_type`

- new functions related to gas griefing mitigations: `get_last_owner_escape_attempt`, get_last_guardian_escape_attempt`

# Version 0.3.1

Support for Transaction V3 that allows paying the transaction fees in STRK token

# Version 0.3.0

First release using Cairo 2

- Renamed functions and events to follow Cairo conventions. Renamed signer to owner to make the role clearer
- Events include more keys for indexing
- Implements the new [SNIP-5](https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-5.md)
- Recovery changes: For extra safety now you need to specify the new signer when triggering the escape. Escapes will automatically expire after a week if not completed
- Outside execution: A new feature to allows metatransactions by leveraging offchain signatures
- This account can only declare Cairo 1 contracts, not allowed to declare Cairo 0 code

More details here https://www.notion.so/argenthq/Starknet-Account-Cairo-1-Release-Notes-dd090b274a874dd4bc70f0da2b05b0f2

# Older versions

This changelog only contains changes starting from version 0.3.0
