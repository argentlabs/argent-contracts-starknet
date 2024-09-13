use argent::linked_set::{LinkedSetMut, LinkedSetTraitMut, LinkedSetMutImpl, LinkedSet, LinkedSetTrait, LinkedSetImpl};
use argent::mocks::multiowner_mock::MultiownerMock;
use argent::multiowner_account::multiowner_account;

use argent::multiowner_account::owner_manager::{owner_manager_component, IOwnerManagerInternal};

use argent::multiowner_account::owner_manager::{owner_manager_component::PrivateTrait, IOwnerManager};
use argent::signer::signer_signature::{Signer, SignerSignature, starknet_signer_from_pubkey};


use argent::signer::{signer_signature::{SignerStorageTrait},};

use argent::signer::{signer_signature::{SignerTrait, SignerStorageValue, SignerSignatureTrait, SignerSpanTrait},};


use argent::utils::{transaction_version::is_estimate_transaction, asserts::assert_only_self};
use starknet::storage::{
    Vec, StoragePointerReadAccess, StoragePointerWriteAccess, MutableVecTrait, StoragePathEntry, Map
};

type ComponentState = owner_manager_component::ComponentState<MultiownerMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    owner_manager_component::component_state_for_testing()
}

#[test]
fn test_add_signer() {
    let mut component = COMPONENT_STATE();
    let a: LinkedSet<SignerStorageValue> = component.owners_storage();
}

