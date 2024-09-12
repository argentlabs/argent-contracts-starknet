Breaking changes:

- Get owner methods:
  backwards compatibility if single owner, but will error otherwise
  fn get_owner() -> felt252;
  fn get_owner_guid() -> felt252;
  fn get_owner_type() -> SignerType;

new methods:

fn get_owner_guids() -> Array<felt252>;
fn get_owner_type(owner_guid: felt252) -> SignerType;
fn get_owner_data(owner_guid: felt252) -> SignerStorageValue;

- Concise signatures (for devs and dexes)
  still working but only if there's a single owner, works with or without guardian

- Owner admin functions
  fn change_owner(new_owner: SignerSignature)` is removed

added  
fn add_owners(owners_to_add: Array<Signer>);
fn remove_owners(owner_guids_to_remove: Array<felt252>) // can't remove self
fn replace_all_owners_with_one(new_owner: SignerSignature); // signature needed to avoid bricking account
might need more: replace_signer to rotate key?

- Recovery
  Owners escaping the guardian is the same, any owner can trigger the escape. A malicious owner can trigger a bad escape, but the bad owner can then be kicked out using a good owner + guardian

Guardian recovering lost account: In this case the escape will remove all owners and add a new one. Notice that if any of the owners was still valid, we wouldn't need recovery at all. So we keep the same interface as before, but now it removes ALL owners before adding a new one

- Sessions
  `is_session_authorization_cached` needs to know which owner was used for in the authorization, so this function now needs to receive either the authorization or the owner_guid used. Caching also uses more storage because it needs to save the owner_guid used. There are other alternatives but they are less backwards compatible

- Edge case
  In the unlikely event where one owner is malicious and the guardian is not responsive, we could improve escaping so
  2 owners can override a guardian escape triggered by 1 owner
  ????? what about gas griefing with bad owner?

OwnerChanged { new_owner: felt252 }
OwnerChangedGuid { new_owner_guid: felt252 }
We can try to keep them if there was a single owner being replaces, but ideally it's removed

New functions like add_owners, remove_owners and replace_all_owners_with_one will emit the existing `OwnerAddedGuid` and `OwnerRemovedGuid`
