## Guardian management:

struct SignerInfo {
signerType: SignerType
guid: felt252
pubkey: Option<felt252>
}

new methods:
get_guardian_guids() -> Array<felt252>
get_guardian_info() -> Array<SignerInfo>
add_guardians(), remove_guardians()

removed all backup guardian methods
change_guardian_backup();
get_guardian_backup(), get_guardian_backup_guid(), get_guardian_backup_type()

methods with changes:
change_guardian(new_guardian: Option<Signer>) renamed to `reset_guardians`
get_guardian, get_guardian_type, get_guardian_guid, might fail if multiple guardians

## ESCAPING:

escaping the guardian will remove ALL existing guardians and optionally add a new one like reset_guardians

## Signatures:

legacy signature used to work if you have a backup guardian, now it will fail if you have multiple guardians (subject to change)
!!! limit to EOA mode??? TODO measure!
other things:

allows other guardian types besides starknet (slightly more expensive to use)

## events

new events GuardianAdded and GuardianRemoved

GuardianChanged and GuardianChangedGuid disappear and are replaced by GuardianAdded + GuardianRemoved
GuardianBackupChanged and GuardianBackupChangedGuid are removed

## Sessions:

tx signature:
would be allowed by any guardian not just the main guardian, mean changes for kulipa
should we enforce that the same guardians signs every tx on the sessions, or is it ok to have different guardians signing it, should at last match the auth sig? YES
