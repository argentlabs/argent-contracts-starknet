## Guardian management:

enum SignerInfo {
signerType: SignerType
guid: felt252
pubkey: Option<felt252>
}

new methods:
get_guardian_guids() -> Array<felt252>
get_guardian_info() -> Array<StorageValue>
add_guardians(), remove_guardians()

removed all backup guardian methods
change_guardian_backup();
get_guardian_backup(), get_guardian_backup_guid(), get_guardian_backup_type()

methods with changes:
change_guardian(new_guardian: Option<Signer>) needs at least a rename maybe to `replace_all_guardians`
get_guardian, get_guardian_type, get_guardian_guid, might fail if multiple guardians

## ESCAPING:

escaping the guardian will remove ALL existing guardians and optionally add a new (ONE ONLY!)

## Signatures:

legacy signature used to work if you have a backup guardian, now it will fail if you have multiple guardians (subject to change)
!!! limit to EOA mode??? TODO measure!
other things:

allows other guardian types besides (slightly more expensive to use)

## events

new events GuardianAdded and GuardianRemoved

GuardianChanged and GuardianChangedGuid dissappear and are replaced by GuardianAdded + GuardianRemoved
GuardianBackupChanged and GuardianBackupChangedGuid are removed

## Sessions:

tx signature:
would be allowed by any guardian not just the main guardian, mean changes for kulipa
should we enforce that the same guardians signs every tx on the sessions, or is it ok to have different guardians signing it, should at last match the auth sig? YES

session signature:

to check if the auth is cached we need to either:

- include the guardian_guid in the session, allows to enforce one particular guardian (not backwards compatible)
- store the guardian_guid when caching: breaks current cache, not efficient
- get the guardian_guid from the auth field: not backwards compatible and doesn't allow to submit tx quickly (need to get the guardian first)
