# Argent Account Changelog

# Version 0.5.0

This version introduces supports for **multiple owners** and **multiple guardians**.
The account requires **one owner** signature **AND** **one guardian** signature if guardians are used (unless calling [escape methods](./argent_account_escape.md#Escape-Methods)).

It also improves **WebAuthn** support compatibility with more browsers.

Make sure you read the **[Upgrades](./argent_account_upgrades.md)** document, as incorrect upgrades can **brick the account**

- **Read methods** were updated to support **multiple owners and guardians**

  Removed:

  ```rust
  fn get_guardian_backup() -> felt252
  fn get_guardian_backup_guid() -> Option<felt252>
  fn get_guardian_backup_type() -> Option<SignerType>
  ```

  Modified: Will panic if there are multiple owners

  ```rust
  fn get_owner() -> felt252;
  fn get_owner_type() -> SignerType;
  fn get_owner_guid() -> felt252;
  ```

  Modified: Will panic if there are multiple guardians

  ```rust
  fn get_guardian() -> felt252
  fn get_guardian_guid() -> Option<felt252>
  fn get_guardian_type() -> Option<SignerType>
  ```

  New read methods to support multiple owners and guardians:

  ```rust
  fn get_owners_guids() -> Array<felt252>
  fn get_owners_info() -> Array<SignerInfo>
  fn get_guardian_guids() -> Array<felt252>
  fn get_guardian_info() -> Array<SignerInfo>

  struct SignerInfo {
      signerType: SignerType
      guid: felt252
      ///Depending on the type it can be a pubkey, a guid or another value. The stored value is unique for each signer type
      stored_value: felt252,
  }
  ```

- **Events** were updated to support **multiple owners and guardians**

  Removed:

  ```
  OwnerChanged, OwnerChangedGuid, GuardianChanged, GuardianChangedGuid, GuardianBackupChanged, GuardianBackupChangedGuid
  ```

  Replaced with new events: (`SignerLinked` event is unchanged)

  ```rust
  struct OwnerAddedGuid {
      #[key]
      new_owner_guid: felt252,
  }

  struct OwnerRemovedGuid {
      #[key]
      removed_owner_guid: felt252,
  }

  struct GuardianAddedGuid {
      #[key]
      new_guardian_guid: felt252,
  }

  struct GuardianRemovedGuid {
      #[key]
      removed_guardian_guid: felt252,
  }

  ```

  The new events will be emitted when **adding or removing** owners or guardians, but also on the account **deployment** and when **upgrading** from older versions. So an external party can just listen to these events to keep track of the owners and guardians.

- **No guardian backup**

  Because of the new multiguardian feature. The concept of guardian backup was removed. During the upgrade any guardian backup will be migrated to be a regular guardian.

  It used to be impossible to remove the main guardian when having a backup guardian. Now the restriction is no longer relevant

  Backup guardians played a different role and couldn't for instance co-sign sessions. Now all guardians are the same

- **Concise signatures**

  Concise signatures are discouraged as they don't support multiple owners or multiple guardians. See [Concise Signatures](./argent_account.md#concise-format)

  Concise signatures used to work only with the main guardian ignoring the backup guardian. Now they only work if there is 0 or 1 guardian

- **Signer management methods** were updated to support multiple owners and guardians

  Removed:

  ```
  change_owner, change_guardian, change_guardian_backup
  ```

  Replaced with:

  ```rust
  fn change_owners(
    owner_guids_to_remove: Array<felt252>,
    owners_to_add: Array<Signer>,
    owner_alive_signature: Option<OwnerAliveSignature>,
  );

  fn change_guardians(
    guardian_guids_to_remove: Array<felt252>,
    guardians_to_add: Array<Signer>,
  );
  ```

  The `change_owners` and `change_guardians` functions will cancel any pending escape (as the old methods did)

  Similar to the old `change_owner`, the new `change_owners` will require a signature from one owner to avoid accidental bricking of the account. But this signature is now optional. More details on [Owner Alive Signature](./owner_alive.md)

- **New escape semantics**

  The escape mechanism remains largely the same, and the methods used to trigger and complete an escape didn't suffer any breaking changes.

  The escape will behave the same if there is only one owner and one guardian. But it's worth explaining how it works with multiple owners and guardians.

  - When an owner escape is completed: ALL the owners are replaced by the single new owner specified in the escape
  - When a guardian escape is completed: ALL the guardians are replaced by the a new guardian specified in the escape. If no new guardian is specified, all the guardians are removed

  See [Escape Process](./argent_account_escape.md)

- **Session changes**

  **Backwards incompatible** if using caching.

  Sessions can now be used with **ANY guardian** were before it was restricted to the main guardian.

  [See More details](sessions.md#History)

- **Session better estimates**

  Added support for [Accurate Estimates](accurate_estimates.md) in the context of sessions

- **WebAuthn Compatibility**

  Increased support for more browsers. Includes breaking changes. [More details](./webauthn.md#history)

- **TransactionExecuted** event was changed

  From:

  ```rust
  struct TransactionExecuted {
      #[key]
      hash: felt252,
      response: Span<Span<felt252>>
  }
  ```

  The response data was removed to make the account more efficient

  ```rust
  struct TransactionExecuted {
    #[key]
    hash: felt252,
  }
  ```

- **Multiple Guardian Types**

  The main guardian was restricted to StarknetSigner before this versions. Now it's possible to use any signer type for the guardians

- **Latest compiler:** Compiled with Cairo v2.10.0

# Version 0.4.0

- **Multiple signer types:** See [Signers and signatures](signers_and_signatures.md)
- **Sessions:** See [Sessions](sessions.md)
- **Outside Execution V2:** See [Outside Execution](outside_execution.md)
- **Configurable escape security period**
  Starting on this version, users can change the security period used for escapes. It will still default to 1 week but it's now possible to change. Changing the security window will also affect the expiration time. For instance changing the security period to 48 hours means that, you need to wait 48h before the update is ready to be completed, and also, it needs to be completed in the following 48h or it will expire
- **Accurate gas estimates:**
  See [Accurate Estimates](accurate_estimates.md). Note that in this version, accurate estimates are not supported for sessions

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
- Escape changes: For extra safety now you need to specify the new signer when triggering the escape. Escapes will automatically expire after a week if not completed
- Outside execution: A new feature to allows metatransactions by leveraging offchain signatures
- This account can only declare Cairo 1 contracts, not allowed to declare Cairo 0 code

More details here https://www.notion.so/argenthq/Starknet-Account-Cairo-1-Release-Notes-dd090b274a874dd4bc70f0da2b05b0f2

# Older versions

This changelog only contains changes starting from version 0.3.0
