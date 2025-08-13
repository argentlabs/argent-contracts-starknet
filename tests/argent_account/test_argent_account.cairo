use argent::multiowner_account::owner_alive::OwnerAliveSignature;
use argent::multiowner_account::{
    argent_account::ArgentAccount, argent_account::ArgentAccount::{MAX_ESCAPE_TIP_STRK, TIME_BETWEEN_TWO_ESCAPES},
    events::{GuardianAddedGuid, GuardianRemovedGuid, OwnerAddedGuid, OwnerRemovedGuid, SignerLinked},
    guardian_manager::guardian_manager_component, owner_manager::owner_manager_component,
};
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::{
    Eip191Signer, Secp256k1Signer, Signer, SignerSignature, SignerTrait, SignerType, StarknetSignature, StarknetSigner,
    starknet_signer_from_pubkey,
};
use argent::utils::serialization::serialize;
use core::num::traits::Zero;
use crate::{
    Felt252TryIntoStarknetSigner, GUARDIAN, ITestArgentAccountDispatcherTrait, OWNER, TX_HASH, initialize_account,
    initialize_account_with, initialize_account_without_guardian, to_starknet_signatures,
};
use snforge_std::{
    EventSpyAssertionsTrait, EventSpyTrait,
    signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}}, spy_events,
    start_cheat_block_timestamp_global, start_cheat_caller_address_global, start_cheat_resource_bounds_global,
    start_cheat_signature_global, start_cheat_tip_global, start_cheat_transaction_hash_global,
    start_cheat_transaction_version_global,
};
use starknet::{ResourcesBounds, account::Call, contract_address_const};

const VALID_UNTIL: u64 = 1100;

fn NEW_OWNER() -> (Signer, OwnerAliveSignature) {
    NEW_OWNER_FROM_KEY('NEW_OWNER')
}

fn NEW_OWNER_FROM_KEY(key: felt252) -> (Signer, OwnerAliveSignature) {
    let new_owner = KeyPairTrait::from_secret_key(key);
    let (r, s) = new_owner.sign(new_owner_message_hash()).unwrap();
    let signer = StarknetSigner { pubkey: new_owner.public_key.try_into().expect('argent/zero-pubkey') };
    (
        Signer::Starknet(signer),
        OwnerAliveSignature {
            owner_signature: SignerSignature::Starknet((signer, StarknetSignature { r, s })),
            signature_expiration: VALID_UNTIL,
        },
    )
}

fn new_owner_message_hash() -> felt252 {
    // Hardcoded hash of the message because get_message_hash_rev_1 uses get_contract_address() and we can't mock it
    // To update it go to src/multiowner_account/owner_alive.cairo and print the hash with
    // hardcoded get_contract_address() to ARGENT_ACCOUNT_ADDRESS
    149168710789768381355964121676254784761481539521088721997114502918124334748
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
fn change_owner() {
    let account = initialize_account();
    let mut spy = spy_events();

    let old_owner_guid = starknet_signer_from_pubkey(OWNER().pubkey).into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    let (signer, _) = NEW_OWNER();
    let (other_signer, _) = NEW_OWNER_FROM_KEY('OTHER_SIGNER');

    account
        .change_owners(
            owner_guids_to_remove: array![old_owner_guid],
            owners_to_add: array![signer, other_signer],
            owner_alive_signature: Option::None,
        );
    let new_owner_guid = signer.into_guid();
    let owners_info = account.get_owners_info();
    assert_eq!(owners_info.len(), 2);
    assert_eq!(*owners_info[0], signer.storage_value().into());
    assert_eq!(*owners_info[1], other_signer.storage_value().into());

    assert_eq!(spy.get_events().events.len(), 5);
    // owner_manager events
    let guid_removed_event = owner_manager_component::Event::OwnerRemovedGuid(
        OwnerRemovedGuid { removed_owner_guid: old_owner_guid },
    );
    let guid_added_event = owner_manager_component::Event::OwnerAddedGuid(OwnerAddedGuid { new_owner_guid });
    let other_guid_added_event = owner_manager_component::Event::OwnerAddedGuid(
        OwnerAddedGuid { new_owner_guid: other_signer.into_guid() },
    );
    spy
        .assert_emitted(
            @array![
                (account.contract_address, guid_removed_event),
                (account.contract_address, guid_added_event),
                (account.contract_address, other_guid_added_event),
            ],
        );

    // ArgentAccount events
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        SignerLinked { signer_guid: new_owner_guid, signer: signer },
    );
    let other_signer_link_event = ArgentAccount::Event::SignerLinked(
        SignerLinked { signer_guid: other_signer.into_guid(), signer: other_signer },
    );
    spy
        .assert_emitted(
            @array![(account.contract_address, signer_link_event), (account.contract_address, other_signer_link_event)],
        );
}

#[test]
fn change_owner_with_alive_signature() {
    let account = initialize_account_without_guardian();

    let old_owner_guid = starknet_signer_from_pubkey(OWNER().pubkey).into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    let (signer, alive_signature) = NEW_OWNER();
    account
        .change_owners(
            owner_guids_to_remove: array![old_owner_guid],
            owners_to_add: array![signer],
            owner_alive_signature: Option::Some(alive_signature),
        );
    let new_owner_guid = signer.into_guid();
    assert_eq!(account.get_owner_guid(), new_owner_guid);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn change_owner_remove_all_owners() {
    let account = initialize_account_without_guardian();

    let old_owner_guid = starknet_signer_from_pubkey(OWNER().pubkey).into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    account
        .change_owners(
            owner_guids_to_remove: array![old_owner_guid], owners_to_add: array![], owner_alive_signature: Option::None,
        );
}

#[test]
fn change_owners_reset_escape() {
    let account = initialize_account();

    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    let (_, not_ready) = account.get_escape_and_status();
    assert_eq!(not_ready, EscapeStatus::NotReady);

    account
        .change_owners(owner_guids_to_remove: array![], owners_to_add: array![], owner_alive_signature: Option::None);

    let (_, none) = account.get_escape_and_status();
    assert_eq!(none, EscapeStatus::None);
}

#[test]
#[should_panic(expected: ('argent/timestamp-too-far-future',))]
fn change_owners_too_far_future() {
    let account = initialize_account();

    let (signer, mut signature) = NEW_OWNER();
    signature.signature_expiration = (60 * 60 * 24) + 1;
    account
        .change_owners(
            owner_guids_to_remove: array![],
            owners_to_add: array![signer],
            owner_alive_signature: Option::Some(signature),
        );
}


#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_owners_only_self() {
    let account = initialize_account();

    start_cheat_caller_address_global(contract_address_const::<42>());
    account.change_owners(array![], array![], Option::None);
}

#[test]
#[should_panic(expected: ('argent/expired-signature',))]
fn change_owners_timestamp_expired() {
    let account = initialize_account();

    let (signer, mut signature) = NEW_OWNER();
    start_cheat_block_timestamp_global(VALID_UNTIL);
    signature.signature_expiration = VALID_UNTIL - 1;
    account
        .change_owners(
            owner_guids_to_remove: array![],
            owners_to_add: array![signer],
            owner_alive_signature: Option::Some(signature),
        );
}

#[test]
#[should_panic(expected: ('argent/invalid-alive-sig',))]
fn change_owners_invalid_signature() {
    let account = initialize_account();

    let (signer, mut signature) = NEW_OWNER();
    let starknet_pubkey = signer.starknet_pubkey_or_none().unwrap();
    signature
        .owner_signature =
            SignerSignature::Starknet(
                (StarknetSigner { pubkey: starknet_pubkey.try_into().unwrap() }, StarknetSignature { r: 42, s: 42 }),
            );

    account
        .change_owners(
            owner_guids_to_remove: array![],
            owners_to_add: array![signer],
            owner_alive_signature: Option::Some(signature),
        );
}

#[test]
#[should_panic(expected: ('argent/invalid-sig-not-owner',))]
fn change_owners_signature_not_from_owner() {
    let account = initialize_account();
    let (_, signature) = NEW_OWNER();
    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![], owner_alive_signature: Option::Some(signature),
        );
}

#[test]
#[should_panic(expected: ('argent/duplicated-guids',))]
fn change_owners_duplicates() {
    let account = initialize_account();
    let current_owner = starknet_signer_from_pubkey(OWNER().pubkey);

    account
        .change_owners(
            owner_guids_to_remove: array![current_owner.into_guid()],
            owners_to_add: array![current_owner],
            owner_alive_signature: Option::None,
        );
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn change_owners_remove_twice() {
    let account = initialize_account();
    let current_owner = starknet_signer_from_pubkey(OWNER().pubkey);

    account
        .change_owners(
            owner_guids_to_remove: array![current_owner.into_guid(), current_owner.into_guid()],
            owners_to_add: array![],
            owner_alive_signature: Option::None,
        );
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn change_owners_add_twice() {
    let account = initialize_account();
    let (signer, _) = NEW_OWNER();

    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![signer, signer], owner_alive_signature: Option::None,
        );
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn change_owners_reach_limits() {
    let account = initialize_account();

    let mut owners_to_add = array![];
    for i in 100..132_u8 {
        let (signer, _) = NEW_OWNER_FROM_KEY(i.into());
        owners_to_add.append(signer)
    };
    account.change_owners(owner_guids_to_remove: array![], :owners_to_add, owner_alive_signature: Option::None);
}

#[test]
fn change_guardians() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    let other_guardian = starknet_signer_from_pubkey(23);
    let mut spy = spy_events();

    account
        .change_guardians(
            guardian_guids_to_remove: array![starknet_signer_from_pubkey(GUARDIAN().pubkey).into_guid()],
            guardians_to_add: array![guardian, other_guardian],
        );
    let guardians_info = account.get_guardians_info();
    assert_eq!(guardians_info.len(), 2);
    assert_eq!(*guardians_info[0], guardian.storage_value().into());
    assert_eq!(*guardians_info[1], other_guardian.storage_value().into());

    assert_eq!(spy.get_events().events.len(), 5);
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        SignerLinked { signer_guid: guardian.into_guid(), signer: guardian },
    );
    let other_signer_link_event = ArgentAccount::Event::SignerLinked(
        SignerLinked { signer_guid: other_guardian.into_guid(), signer: other_guardian },
    );
    let guardian_removed_event = guardian_manager_component::Event::GuardianRemovedGuid(
        GuardianRemovedGuid { removed_guardian_guid: starknet_signer_from_pubkey(GUARDIAN().pubkey).into_guid() },
    );
    let guardian_added_event = guardian_manager_component::Event::GuardianAddedGuid(
        GuardianAddedGuid { new_guardian_guid: guardian.into_guid() },
    );
    let other_guardian_added_event = guardian_manager_component::Event::GuardianAddedGuid(
        GuardianAddedGuid { new_guardian_guid: other_guardian.into_guid() },
    );
    spy
        .assert_emitted(
            @array![(account.contract_address, signer_link_event), (account.contract_address, other_signer_link_event)],
        );
    spy
        .assert_emitted(
            @array![
                (account.contract_address, guardian_removed_event),
                (account.contract_address, guardian_added_event),
                (account.contract_address, other_guardian_added_event),
            ],
        );
}

#[test]
fn change_guardians_remove_all_guardians() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    let other_guardian = starknet_signer_from_pubkey(23);

    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![guardian, other_guardian]);

    account
        .change_guardians(
            guardian_guids_to_remove: array![
                starknet_signer_from_pubkey(GUARDIAN().pubkey).into_guid(),
                guardian.into_guid(),
                other_guardian.into_guid(),
            ],
            guardians_to_add: array![],
        );

    assert_eq!(account.get_guardians_info(), array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn change_guardians_reach_limits() {
    let account = initialize_account();

    let mut guardians_to_add = array![];
    for i in 100..132_u8 {
        let signer = starknet_signer_from_pubkey(i.into());
        guardians_to_add.append(signer)
    };

    account.change_guardians(guardian_guids_to_remove: array![], :guardians_to_add);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn change_guardians_remove_twice() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(GUARDIAN().pubkey);

    account
        .change_guardians(
            guardian_guids_to_remove: array![guardian.into_guid(), guardian.into_guid()], guardians_to_add: array![],
        );
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn change_guardians_add_twice() {
    let account = initialize_account();
    let new_guardian = starknet_signer_from_pubkey(23);

    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![new_guardian, new_guardian]);
}

#[test]
#[should_panic(expected: ('argent/duplicated-guids',))]
fn change_guardians_duplicates() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(GUARDIAN().pubkey);
    account
        .change_guardians(guardian_guids_to_remove: array![guardian.into_guid()], guardians_to_add: array![guardian]);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_guardians_only_self() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![guardian]);
}

#[test]
#[should_panic(expected: ('argent/multiple-owners',))]
fn get_owner_multiple_owners() {
    let account = initialize_account();
    let signer = starknet_signer_from_pubkey(22);

    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![signer], owner_alive_signature: Option::None,
        );

    assert_eq!(account.get_owners_info().len(), 2);
    account.get_owner();
}

#[test]
#[should_panic(expected: ('argent/multiple-owners',))]
fn get_owner_type_multiple_owners() {
    let account = initialize_account();
    let signer = starknet_signer_from_pubkey(22);

    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![signer], owner_alive_signature: Option::None,
        );

    assert_eq!(account.get_owners_info().len(), 2);
    account.get_owner_type();
}

#[test]
#[should_panic(expected: ('argent/multiple-owners',))]
fn get_owner_guid_multiple_owners() {
    let account = initialize_account();
    let signer = starknet_signer_from_pubkey(22);

    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![signer], owner_alive_signature: Option::None,
        );

    assert_eq!(account.get_owners_info().len(), 2);
    account.get_owner_guid();
}

#[test]
fn get_guardian() {
    let account = initialize_account();

    let guardian = account.get_guardian();
    assert_eq!(guardian, GUARDIAN().pubkey);
}

#[test]
#[should_panic(expected: ('argent/multiple-guardians',))]
fn get_guardian_multiple_guardians() {
    let account = initialize_account();
    let signer = starknet_signer_from_pubkey(22);

    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![signer]);

    assert_eq!(account.get_guardians_info().len(), 2);
    account.get_guardian();
}

#[test]
fn get_guardian_no_guardian() {
    let account = initialize_account_without_guardian();

    let guardian = account.get_guardian();
    assert_eq!(guardian, 0);
}

#[test]
fn get_guardian_type() {
    let account = initialize_account();

    let guardian_type = account.get_guardian_type();
    assert_eq!(guardian_type, Option::Some(SignerType::Starknet));
}

#[test]
fn get_guardian_type_no_guardian() {
    let account = initialize_account_without_guardian();

    let guardian_type = account.get_guardian_type();
    assert_eq!(guardian_type, Option::None);
}

#[test]
#[should_panic(expected: ('argent/multiple-guardians',))]
fn get_guardian_type_multiple_guardians() {
    let account = initialize_account();
    let signer = starknet_signer_from_pubkey(22);

    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![signer]);

    assert_eq!(account.get_guardians_info().len(), 2);
    let _ = account.get_guardian_type();
}

#[test]
fn get_guardian_guid() {
    let account = initialize_account();

    let guardian_guid = account.get_guardian_guid().expect('missing guardian');
    assert_eq!(guardian_guid, starknet_signer_from_pubkey(GUARDIAN().pubkey).into_guid());
}

#[test]
fn get_guardian_guid_no_guardian() {
    let account = initialize_account_without_guardian();

    let guardian_guid = account.get_guardian_guid();
    assert_eq!(guardian_guid, Option::None);
}

#[test]
#[should_panic(expected: ('argent/multiple-guardians',))]
fn get_guardian_guid_multiple_guardians() {
    let account = initialize_account();
    let signer = starknet_signer_from_pubkey(22);

    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![signer]);

    assert_eq!(account.get_guardians_info().len(), 2);
    let _ = account.get_guardian_guid();
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
        "SRC5_INTERFACE_ID",
    );
    assert_eq!(account.supportsInterface(0xa66bd575), 1);
    assert_eq!(account.supportsInterface(0x3943f10f), 1);
    assert_eq!(
        account.supportsInterface(0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd),
        1,
        "SRC5_ACCOUNT_INTERFACE_ID",
    );

    assert_eq!(
        account.supportsInterface(0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0",
    );
    assert_eq!(
        account.supportsInterface(0x1d1144bb2138366ff28d8e9ab57456b1d332ac42196230c3a602003c89872),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1",
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

#[test]
#[should_panic(expected: ('argent/tip-too-high',))]
fn test_max_tip() {
    let account = initialize_account();

    start_cheat_caller_address_global(Zero::zero());
    start_cheat_transaction_version_global(3);

    // We need tip * max_amount <= MAX_ESCAPE_TIP_STRK
    start_cheat_tip_global(1);
    let max_amount = MAX_ESCAPE_TIP_STRK.try_into().unwrap() + 1;
    let resource_bounds: Array<ResourcesBounds> = array![
        ResourcesBounds { resource: 'L2_GAS', max_amount, max_price_per_unit: 1 },
    ];
    start_cheat_resource_bounds_global(resource_bounds.span());

    start_cheat_transaction_hash_global(TX_HASH);
    start_cheat_signature_global(to_starknet_signatures(array![OWNER()]).span());

    start_cheat_block_timestamp_global(TIME_BETWEEN_TWO_ESCAPES + 1);

    let call = Call {
        selector: selector!("trigger_escape_guardian"),
        to: account.contract_address,
        calldata: serialize(@Option::<Signer>::None).span(),
    };

    account.__validate__(array![call]);
}

#[test]
fn test_max_tip_on_limit() {
    let account = initialize_account();

    start_cheat_caller_address_global(Zero::zero());
    start_cheat_transaction_version_global(3);

    // We need tip * max_amount <= MAX_ESCAPE_TIP_STRK
    start_cheat_tip_global(1);
    let max_amount = MAX_ESCAPE_TIP_STRK.try_into().unwrap();
    let resource_bounds: Array<ResourcesBounds> = array![
        ResourcesBounds { resource: 'L2_GAS', max_amount, max_price_per_unit: 1 },
    ];
    start_cheat_resource_bounds_global(resource_bounds.span());

    start_cheat_transaction_hash_global(TX_HASH);
    start_cheat_signature_global(to_starknet_signatures(array![OWNER()]).span());

    start_cheat_block_timestamp_global(TIME_BETWEEN_TWO_ESCAPES + 1);

    let call = Call {
        selector: selector!("trigger_escape_guardian"),
        to: account.contract_address,
        calldata: serialize(@Option::<Signer>::None).span(),
    };

    account.__validate__(array![call]);
}
