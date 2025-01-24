use argent::multiowner_account::owner_alive::OwnerAlive;
use argent::multiowner_account::{
    events::{OwnerAddedGuid, OwnerRemovedGuid}, owner_manager::owner_manager_component,
    guardian_manager::guardian_manager_component, argent_account::ArgentAccount
};
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::{
    StarknetSigner, Signer, SignerSignature, SignerSignatureTrait, StarknetSignature, SignerTrait,
    starknet_signer_from_pubkey, Secp256k1Signer, Eip191Signer
};

use hash::{HashStateTrait, HashStateExTrait};
use pedersen::PedersenTrait;
use snforge_std::{
    start_cheat_block_timestamp_global,
    signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}},
    start_cheat_caller_address_global, start_cheat_transaction_version_global, EventSpyTrait, EventSpyAssertionsTrait,
    spy_events
};
use starknet::contract_address_const;
use super::super::{
    ARGENT_ACCOUNT_ADDRESS, ITestArgentAccountDispatcherTrait, initialize_account_with, initialize_account,
    initialize_account_without_guardian, Felt252TryIntoStarknetSigner, OWNER, GUARDIAN, WRONG_OWNER
};

const VALID_UNTIL: u64 = 1100;

fn NEW_OWNER() -> (StarknetSigner, StarknetSignature) {
    let new_owner = KeyPairTrait::from_secret_key('NEW_OWNER');
    let (r, s) = new_owner.sign(new_owner_message_hash()).unwrap();
    let pubkey = new_owner.public_key.try_into().expect('argent/zero-pubkey');
    (StarknetSigner { pubkey }, StarknetSignature { r, s })
}

fn new_owner_message_hash() -> felt252 {
    // Hardcoded hash of the message because get_message_hash_rev_1 uses get_contract_address() and we can't mock it
    // To update it go to src/multiowner_account/replace_owners_message.cairo and print the hash with
    // hardcoded get_contract_address() to ARGENT_ACCOUNT_ADDRESS
    1276015325954735817330442780660672625383852586659503239691558137778155209517
}


#[test]
fn initialize() {
    let account = initialize_account_with(1, 2);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid());
    assert_eq!(account.get_guardian_guid().unwrap(), starknet_signer_from_pubkey(2).into_guid());
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn check_transaction_version_on_execute() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<0>());
    start_cheat_transaction_version_global(32);
    account.__execute__(array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn check_transaction_version_on_validate() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<0>());
    start_cheat_transaction_version_global(32);
    account.__validate__(array![]);
}

#[test]
fn initialized_no_guardian() {
    let account = initialize_account_with(1, 0);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid());
    assert!(account.get_guardian_guid().is_none());
}

#[test]
fn erc165_unsupported_interfaces() {
    let account = initialize_account();
    assert!(!account.supports_interface(0));
    assert!(!account.supports_interface(0xffffffff));
}

#[test]
fn reset_owners() {
    let account = initialize_account();
    let mut spy = spy_events();

    let old_owner_guid = starknet_signer_from_pubkey(OWNER().pubkey).into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.reset_owners(signer_signature, VALID_UNTIL);

    let new_owner_guid = signer_signature.signer().into_guid();
    assert_eq!(account.get_owner_guid(), new_owner_guid);

    assert_eq!(spy.get_events().events.len(), 3);

    // owner_manager events
    let guid_removed_event = owner_manager_component::Event::OwnerRemovedGuid(
        owner_manager_component::OwnerRemovedGuid { removed_owner_guid: old_owner_guid }
    );
    let guid_added_event = owner_manager_component::Event::OwnerAddedGuid(
        owner_manager_component::OwnerAddedGuid { new_owner_guid }
    );
    spy
        .assert_emitted(
            @array![(account.contract_address, guid_removed_event), (account.contract_address, guid_added_event),]
        );

    // ArgentAccount events
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        ArgentAccount::SignerLinked { signer_guid: new_owner_guid, signer: signer_signature.signer() }
    );
    spy.assert_emitted(@array![(account.contract_address, signer_link_event)]);
}

#[test]
fn reset_owners_reset_escape() {
    let account = initialize_account();

    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    let (_, not_ready) = account.get_escape_and_status();
    assert_eq!(not_ready, EscapeStatus::NotReady);

    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.reset_owners(signer_signature, VALID_UNTIL);

    let (_, none) = account.get_escape_and_status();
    assert_eq!(none, EscapeStatus::None);
}

#[test]
#[should_panic(expected: ('argent/timestamp-too-far-future',))]
fn reset_owners_too_far_future() {
    let account = initialize_account();

    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.reset_owners(signer_signature, (60 * 60 * 24) + 1);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn reset_owners_only_self() {
    let account = initialize_account();

    start_cheat_caller_address_global(contract_address_const::<42>());
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.reset_owners(signer_signature, VALID_UNTIL);
}

#[test]
#[should_panic(expected: ('argent/expired-signature',))]
fn reset_owners_timestamp_expired() {
    let account = initialize_account();

    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    start_cheat_block_timestamp_global(VALID_UNTIL);
    account.reset_owners(signer_signature, VALID_UNTIL - 1);
}

#[test]
#[should_panic(expected: ('argent/invalid-new-owner-sig',))]
fn reset_owners_invalid_message() {
    let account = initialize_account();
    let (signer, _) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet(
        (signer, StarknetSignature { r: WRONG_OWNER().sig.r, s: WRONG_OWNER().sig.s })
    );
    account.reset_owners(signer_signature, VALID_UNTIL);
}

#[test]
#[should_panic(expected: ('argent/invalid-new-owner-sig',))]
fn reset_owners_wrong_pub_key() {
    let account = initialize_account();
    let (_, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((WRONG_OWNER().pubkey.try_into().unwrap(), signature));
    account.reset_owners(signer_signature, VALID_UNTIL);
}

#[test]
fn reset_guardians() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    let mut spy = spy_events();

    account.reset_guardians(Option::Some(guardian));
    assert_eq!(account.get_guardian(), 22);

    assert_eq!(spy.get_events().events.len(), 3);
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        ArgentAccount::SignerLinked { signer_guid: guardian.into_guid(), signer: guardian }
    );
    let guardian_removed_event = guardian_manager_component::Event::GuardianRemovedGuid(
        guardian_manager_component::GuardianRemovedGuid {
            removed_guardian_guid: starknet_signer_from_pubkey(GUARDIAN().pubkey).into_guid()
        }
    );
    let guardian_added_event = guardian_manager_component::Event::GuardianAddedGuid(
        guardian_manager_component::GuardianAddedGuid { new_guardian_guid: guardian.into_guid() }
    );
    spy.assert_emitted(@array![(account.contract_address, signer_link_event)]);
    spy
        .assert_emitted(
            @array![
                (account.contract_address, guardian_removed_event), (account.contract_address, guardian_added_event)
            ]
        );
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn reset_guardians_only_self() {
    let account = initialize_account();
    let guardian = Option::Some(starknet_signer_from_pubkey(22));
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.reset_guardians(guardian);
}

#[test]
fn reset_guardians_to_zero() {
    let account = initialize_account();
    account.reset_guardians(Option::None);
    assert!(account.get_guardian().is_zero());
}

#[test]
fn get_version() {
    let version = initialize_account().get_version();
    assert_eq!(version.major, 0);
    assert_eq!(version.minor, 5);
    assert_eq!(version.patch, 0);
}

#[test]
fn getVersion() {
    assert_eq!(initialize_account().getVersion(), '0.5.0');
}

#[test]
fn get_name() {
    assert_eq!(initialize_account().get_name(), 'ArgentAccount');
}

#[test]
fn getName() {
    assert_eq!(initialize_account().getName(), 'ArgentAccount');
}

#[test]
fn unsupported_supportsInterface() {
    let account = initialize_account();
    assert_eq!(account.supportsInterface(0), 0);
    assert_eq!(account.supportsInterface(0xffffffff), 0);
}

#[test]
fn supportsInterface() {
    let account = initialize_account();
    assert_eq!(account.supportsInterface(0x01ffc9a7), 1);
    assert_eq!(
        account.supportsInterface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        1,
        "SRC5_INTERFACE_ID"
    );
    assert_eq!(account.supportsInterface(0xa66bd575), 1);
    assert_eq!(account.supportsInterface(0x3943f10f), 1);
    assert_eq!(
        account.supportsInterface(0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd),
        1,
        "SRC5_ACCOUNT_INTERFACE_ID"
    );

    assert_eq!(
        account.supportsInterface(0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0"
    );
    assert_eq!(
        account.supportsInterface(0x1d1144bb2138366ff28d8e9ab57456b1d332ac42196230c3a602003c89872),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1"
    );
}

#[test]
#[should_panic(expected: ('argent/non-null-caller',))]
fn cant_call_validate() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.__validate__(array![]);
}

#[test]
#[should_panic(expected: ('argent/zero-pubkey-hash',))]
fn test_signer_secp256k1_wrong_pubkey_hash() {
    let account = initialize_account();

    let x = Signer::Secp256k1(Secp256k1Signer { pubkey_hash: 0.try_into().unwrap() });
    account.trigger_escape_owner(x);
}


#[test]
#[should_panic(expected: ('argent/zero-eth-EthAddress',))]
fn test_signer_eip191Signer_wrong_pubkey_hash() {
    let account = initialize_account();

    let x = Signer::Eip191(Eip191Signer { eth_address: 0.try_into().unwrap() });
    account.trigger_escape_owner(x);
}
