mod test_multisig_account;
mod test_multisig_remove_signers;
mod test_multisig_replace_signers;
mod test_multisig_signing;

use multisig::ArgentMultisig;

const signer_pubkey_1: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_pubkey_2: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;

use array::{ArrayTrait, SpanTrait};
use traits::{TryInto, Into};
use option::OptionTrait;
use result::ResultTrait;
use starknet::{
    contract_address_const, syscalls::deploy_syscall, account::Call, testing::set_contract_address
};
use lib::Version;

#[starknet::interface]
trait ITestArgentMultisig<TContractState> {
    // IAccount
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    // ITestArgentMultisig
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252;
    // External
    fn change_threshold(ref self: TContractState, new_threshold: usize);
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<felt252>);
    fn remove_signers(
        ref self: TContractState, new_threshold: usize, signers_to_remove: Array<felt252>
    );
    fn replace_signer(ref self: TContractState, signer_to_remove: felt252, signer_to_add: felt252);
    // Views
    fn get_name(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn getVersion(self: @TContractState) -> felt252;
    fn get_threshold(self: @TContractState) -> usize;
    fn get_signers(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: felt252) -> bool;
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn assert_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    );
    fn is_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool;

    fn is_valid_signature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
    fn isValidSignature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}

fn initialize_multisig() -> ITestArgentMultisigDispatcher {
    let threshold = 1;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    signers_array.append(signer_pubkey_2);
    signers_array.append(signer_pubkey_3);
    initialize_multisig_with(threshold, signers_array.span())
}

fn initialize_multisig_with_one_signer() -> ITestArgentMultisigDispatcher {
    let threshold = 1;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    initialize_multisig_with(threshold, signers_array.span())
}

fn initialize_multisig_with(
    threshold: usize, mut signers: Span<felt252>
) -> ITestArgentMultisigDispatcher {
    let mut calldata = ArrayTrait::new();
    calldata.append(threshold.into());
    calldata.append(signers.len().into());
    loop {
        match signers.pop_front() {
            Option::Some(signer) => {
                calldata.append(*signer)
            },
            Option::None(()) => {
                break;
            },
        };
    };

    let class_hash = ArgentMultisig::TEST_CLASS_HASH.try_into().unwrap();
    let (contract_address, _) = deploy_syscall(class_hash, 0, calldata.span(), true).unwrap();

    // This will set the caller for subsequent calls (avoid 'argent/only-self')
    set_contract_address(contract_address_const::<1>());
    ITestArgentMultisigDispatcher { contract_address }
}
