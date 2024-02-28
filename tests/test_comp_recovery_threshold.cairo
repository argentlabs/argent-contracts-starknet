// use core::traits::TryInto;
// use argent::multisig::interface::IArgentMultisigInternal;
// use argent::multisig::interface::{IArgentMultisig, IArgentMultisigDispatcher, IArgentMultisigDispatcherTrait};
// use argent::recovery::interface::{IRecovery, IRecoveryDispatcher, IRecoveryDispatcherTrait, EscapeStatus};
// use argent::recovery::threshold_recovery::{
//     IToggleThresholdRecovery, IToggleThresholdRecoveryDispatcher, IToggleThresholdRecoveryDispatcherTrait
// };
// use argent::recovery::{threshold_recovery::threshold_recovery_component};
// use argent::signer::{signer_signature::{Signer, StarknetSigner, IntoGuid}};
// use argent::signer_storage::signer_list::signer_list_component;
// use super::mocks::recovery_mocks::ThresholdRecoveryMock;
// use starknet::SyscallResultTrait;
// use starknet::{
//     deploy_syscall, ContractAddress, contract_address_const, testing::{set_contract_address, set_caller_address, set_block_timestamp}
// };

// const signer_pubkey_1: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
// const signer_pubkey_2: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
// const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;

// fn SIGNER_1() -> Signer {
//     Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 })
// }

// fn SIGNER_2() -> Signer {
//     Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 })
// }

// fn SIGNER_3() -> Signer {
//     Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_3 })
// }

// fn setup() -> (IRecoveryDispatcher, IToggleThresholdRecoveryDispatcher, IArgentMultisigDispatcher) {
//     let (address, _) = deploy_syscall(
//         ThresholdRecoveryMock::TEST_CLASS_HASH.try_into().unwrap(), 0, array![].span(), false
//     )
//         .unwrap_syscall();
//     set_contract_address(address);
//       let a  = array![0x123, 0x123, 0x123].span();
//       let b: ContractAddress = (*a.at(0)).try_into().unwrap();
//     IArgentMultisigDispatcher { contract_address: address }.add_signers(2, array![SIGNER_1(), SIGNER_2()]);
//     IToggleThresholdRecoveryDispatcher { contract_address: address }.toggle_escape(true, 10, 10);
//     (
//         IRecoveryDispatcher { contract_address: address },
//         IToggleThresholdRecoveryDispatcher { contract_address: address },
//         IArgentMultisigDispatcher { contract_address: address }
//     )

// }

// // Toggle 

// #[test]
// fn test_toggle_escape() {
//     let (component, toggle_component, _) = setup();
//     let mut config = component.get_escape_enabled();
//     assert(config.is_enabled == 1, 'should be enabled');
//     assert(config.security_period == 10, 'should be 10');
//     assert(config.expiry_period == 10, 'should be 10');
//     toggle_component.toggle_escape(false, 0, 0);
//     config = component.get_escape_enabled();
//     assert(config.is_enabled == 0, 'should not be enabled');
//     assert(config.security_period == 0, 'should be 0');
//     assert(config.expiry_period == 0, 'should be 0');
// }

// #[test]
// #[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
// fn test_toggle_unauthorised() {
//     let (component, toggle_component, _) = setup();
//     set_contract_address(42.try_into().unwrap());
//     toggle_component.toggle_escape(false, 0, 0);
// }

// // Trigger

// #[test]
// fn test_trigger_escape_first_signer() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_1()], array![SIGNER_3()]);
//     let (escape, status) = component.get_escape();
//     assert(*escape.target_signers.at(0) == signer_pubkey_1, 'should be signer 1');
//     assert(*escape.new_signers.at(0) == signer_pubkey_3, 'should be signer 3');
//     assert(escape.ready_at == 10, 'should be 10');
//     assert(status == EscapeStatus::NotReady, 'should be NotReady');
// }

// #[test]
// fn test_trigger_escape_last_signer() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     let (escape, status) = component.get_escape();
//     assert(*escape.target_signers.at(0) == signer_pubkey_2, 'should be signer 2');
//     assert(*escape.new_signers.at(0) == signer_pubkey_3, 'should be signer 3');
//     assert(escape.ready_at == 10, 'should be 10');
//     assert(status == EscapeStatus::NotReady, 'should be NotReady');
// }

// #[test]
// fn test_trigger_escape_can_override() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_1()], array![SIGNER_3()]);
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     let (escape, status) = component.get_escape();
//     assert(*escape.target_signers.at(0) == signer_pubkey_2, 'should be signer 2');
//     assert(*escape.new_signers.at(0) == signer_pubkey_3, 'should be signer 3');
// }

// #[test]
// #[should_panic(expected: ('argent/cannot-override-escape', 'ENTRYPOINT_FAILED'))]
// fn test_trigger_escape_cannot_override() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     component.trigger_escape(array![SIGNER_1()], array![SIGNER_3()]);
// }

// #[test]
// #[should_panic(expected: ('argent/invalid-escape-length', 'ENTRYPOINT_FAILED'))]
// fn test_trigger_escape_invalid_input() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3(), SIGNER_1()]);
// }

// #[test]
// #[should_panic(expected: ('argent/escape-disabled', 'ENTRYPOINT_FAILED'))]
// fn test_trigger_escape_not_enabled() {
//     let (component, toggle_component, _) = setup();
//     toggle_component.toggle_escape(false, 0, 0);
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
// }

// #[test]
// #[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
// fn test_trigger_escape_unauthorised() {
//     let (component, _, _) = setup();
//     set_contract_address(42.try_into().unwrap());
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
// }

// // Escape

// #[test]
// fn test_execute_escape() {
//     let (component, _, multisig_component) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     set_block_timestamp(11);
//     component.execute_escape();
//     let (escape, status) = component.get_escape();
//     assert(status == EscapeStatus::None, 'status should be None');
//     assert(escape.ready_at == 0, 'should be no recovery');
//     assert(multisig_component.is_signer(SIGNER_1()), 'should be signer 1');
//     assert(multisig_component.is_signer(SIGNER_3()), 'should be signer 3');
//     assert(!multisig_component.is_signer(SIGNER_2()), 'should not be signer 2');
// }

// #[test]
// #[should_panic(expected: ('argent/invalid-escape', 'ENTRYPOINT_FAILED'))]
// fn test_execute_escape_NotReady() {
//     let (component, _, multisig_component) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     set_block_timestamp(8);
//     component.execute_escape();
// }

// #[test]
// #[should_panic(expected: ('argent/invalid-escape', 'ENTRYPOINT_FAILED'))]
// fn test_execute_escape_Expired() {
//     let (component, _, multisig_component) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     set_block_timestamp(28);
//     component.execute_escape();
// }

// #[test]
// #[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
// fn test_execute_escape_unauthorised() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     set_block_timestamp(11);
//     set_contract_address(42.try_into().unwrap());
//     component.execute_escape();
// }

// // Cancel

// #[test]
// fn test_cancel_escape() {
//     let (component, _, multisig_component) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     set_block_timestamp(11);
//     component.cancel_escape();
//     let (escape, status) = component.get_escape();
//     assert(status == EscapeStatus::None, 'status should be None');
//     assert(escape.ready_at == 0, 'should be no recovery');
//     assert(multisig_component.is_signer(SIGNER_1()), 'should be signer 1');
//     assert(multisig_component.is_signer(SIGNER_2()), 'should be signer 2');
//     assert(!multisig_component.is_signer(SIGNER_3()), 'should not be signer 3');
// }

// #[test]
// #[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
// fn test_cancel_escape_unauthorised() {
//     let (component, _, _) = setup();
//     component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
//     set_block_timestamp(11);
//     set_contract_address(42.try_into().unwrap());
//     component.cancel_escape();
// }


