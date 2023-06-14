use array::{ArrayTrait, SpanTrait};
use traits::TryInto;
use option::OptionTrait;
use result::ResultTrait;

use starknet::{contract_address_const, deploy_syscall, Felt252TryIntoClassHash};
use starknet::testing::{set_block_number};

use lib::{Call, execute_multicall, TestDapp};
use multicall::aggregate;
use debug::PrintTrait;


#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/multicall-failed', 0, 'CONTRACT_NOT_DEPLOYED'))]
fn execute_multicall_simple() {
    let call = Call {
        to: contract_address_const::<42>(), selector: 43, calldata: ArrayTrait::new()
    };

    let mut arr = ArrayTrait::new();
    arr.append(call);
    execute_multicall(arr.span());
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/multicall-failed', 2, 'test dapp reverted', 'ENTRYPOINT_FAILED'))]
fn execute_multicall_at_one() {
    let calldataDeploy = ArrayTrait::new();
    let (address0, _) = deploy_syscall(
        TestDapp::TEST_CLASS_HASH.try_into().unwrap(), 0, calldataDeploy.span(), false
    )
        .unwrap();

    let mut calldata1 = ArrayTrait::new();
    calldata1.append(12);
    let call1 = Call {
        to: address0,
        selector: 1257997212343903061729138261393903607425919870525153789348007715635666768741, // set_number(number)
        calldata: calldata1
    };

    let mut calldata2 = ArrayTrait::new();
    calldata2.append(12);
    let call2 = Call {
        to: address0,
        selector: 966438596990474552217413352546537164754794065595593730315125915414067970214, // increase_number(number)
        calldata: calldata2
    };

    let mut calldata3 = ArrayTrait::new();
    calldata3.append(12);
    let call3 = Call {
        to: address0,
        selector: 1378405772398747753825744346429351463310669626437442629621279049660910933566, // throw_error(number)
        calldata: calldata3
    };

    let mut arr = ArrayTrait::new();
    arr.append(call1);
    arr.append(call2);
    arr.append(call3);
    execute_multicall(arr.span());
}

