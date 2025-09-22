use argent::multiowner_account::owner_alive::{OwnerAlive, OwnerAliveSignature};
use argent::multiowner_account::{
    argent_account::ArgentAccount, events::{OwnerAddedGuid, OwnerRemovedGuid, SignerLinked},
    owner_manager::owner_manager_component,
};
use argent::offchain_message::{IStructHashRev1, StarknetDomain};
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::{
    SignerSignature, SignerSignatureTrait, SignerTrait, StarknetSignature, StarknetSigner,
};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use crate::{
    ArgentAccountSetup, ArgentAccountWithoutGuardianSetup, ITestArgentAccountDispatcherTrait, SignerKeyPairImpl,
    StarknetKeyPair, initialize_account, initialize_account_without_guardian,
};
use snforge_std::{
    EventSpyAssertionsTrait, EventSpyTrait, spy_events, start_cheat_block_timestamp_global,
    start_cheat_caller_address_global,
};
use starknet::ContractAddress;

const VALID_UNTIL: u64 = 1100;

fn new_owner_alive_signature(contract_address: ContractAddress) -> OwnerAliveSignature {
    let owner = StarknetKeyPair::random();

    let new_owner_guid = owner.into_guid();
    let signature_expiration = VALID_UNTIL;
    let message_hash = get_test_owner_alive_message_hash(
        OwnerAlive { new_owner_guid, signature_expiration }, contract_address,
    );
    let owner_signature = owner.sign(message_hash);

    OwnerAliveSignature { owner_signature, signature_expiration }
}

fn get_test_owner_alive_message_hash(owner_alive: OwnerAlive, contract_address: ContractAddress) -> felt252 {
    let chain_id = 'SN_SEPOLIA';
    let domain = StarknetDomain { name: 'Owner Alive', version: '1', chain_id, revision: 1 };
    PoseidonTrait::new()
        .update_with('StarkNet Message')
        .update_with(domain.get_struct_hash_rev_1())
        .update_with(contract_address)
        .update_with(owner_alive.get_struct_hash_rev_1())
        .finalize()
}

#[test]
fn change_owner() {
    let ArgentAccountSetup { account, owners, .. } = initialize_account();
    let mut spy = spy_events();

    let old_owner_guid = owners[0].into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    let signer = StarknetKeyPair::random().signer();
    let other_signer = StarknetKeyPair::random().signer();

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
    let ArgentAccountWithoutGuardianSetup { account, owners } = initialize_account_without_guardian();

    let old_owner_guid = owners[0].into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    let alive_signature = new_owner_alive_signature(account.contract_address);
    let signer = alive_signature.owner_signature.signer();

    account
        .change_owners(
            owner_guids_to_remove: array![old_owner_guid],
            owners_to_add: array![alive_signature.owner_signature.signer()],
            owner_alive_signature: Option::Some(alive_signature),
        );
    let new_owner_guid = signer.into_guid();
    assert_eq!(account.get_owner_guid(), new_owner_guid);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn change_owner_remove_all_owners() {
    let ArgentAccountWithoutGuardianSetup { account, owners } = initialize_account_without_guardian();

    let old_owner_guid = owners[0].into_guid();
    assert_eq!(account.get_owner_guid(), old_owner_guid);

    account
        .change_owners(
            owner_guids_to_remove: array![old_owner_guid], owners_to_add: array![], owner_alive_signature: Option::None,
        );
}

#[test]
fn change_owners_reset_escape() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    account.trigger_escape_owner(StarknetKeyPair::random().signer());
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
    let ArgentAccountSetup { account, .. } = initialize_account();

    let mut signature = new_owner_alive_signature(account.contract_address);
    signature.signature_expiration = (60 * 60 * 24) + 1;

    account
        .change_owners(
            owner_guids_to_remove: array![],
            owners_to_add: array![signature.owner_signature.signer()],
            owner_alive_signature: Option::Some(signature),
        );
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_owners_only_self() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    start_cheat_caller_address_global(42.try_into().unwrap());
    account.change_owners(array![], array![], Option::None);
}

#[test]
#[should_panic(expected: ('argent/expired-signature',))]
fn change_owners_timestamp_expired() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let mut signature = new_owner_alive_signature(account.contract_address);
    start_cheat_block_timestamp_global(VALID_UNTIL);
    signature.signature_expiration = VALID_UNTIL - 1;

    account
        .change_owners(
            owner_guids_to_remove: array![],
            owners_to_add: array![signature.owner_signature.signer()],
            owner_alive_signature: Option::Some(signature),
        );
}

#[test]
#[should_panic(expected: ('argent/invalid-alive-sig',))]
fn change_owners_invalid_signature() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let mut signature = new_owner_alive_signature(account.contract_address);
    let signer = signature.owner_signature.signer();
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
    let ArgentAccountSetup { account, .. } = initialize_account();
    let mut signature = new_owner_alive_signature(account.contract_address);
    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![], owner_alive_signature: Option::Some(signature),
        );
}

#[test]
#[should_panic(expected: ('argent/duplicated-guids',))]
fn change_owners_duplicates() {
    let ArgentAccountSetup { account, owners, .. } = initialize_account();
    let owner = owners[0];
    account
        .change_owners(
            owner_guids_to_remove: array![owner.into_guid()],
            owners_to_add: array![owner.signer()],
            owner_alive_signature: Option::None,
        );
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn change_owners_remove_twice() {
    let ArgentAccountSetup { account, owners, .. } = initialize_account();
    let owner = owners[0];

    account
        .change_owners(
            owner_guids_to_remove: array![owner.into_guid(), owner.into_guid()],
            owners_to_add: array![],
            owner_alive_signature: Option::None,
        );
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn change_owners_add_twice() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let signer = StarknetKeyPair::random().signer();

    account
        .change_owners(
            owner_guids_to_remove: array![], owners_to_add: array![signer, signer], owner_alive_signature: Option::None,
        );
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn change_owners_reach_limits() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let mut owners_to_add = array![];
    for _ in 100..132_u8 {
        owners_to_add.append(StarknetKeyPair::random().signer())
    };
    account.change_owners(owner_guids_to_remove: array![], :owners_to_add, owner_alive_signature: Option::None);
}
