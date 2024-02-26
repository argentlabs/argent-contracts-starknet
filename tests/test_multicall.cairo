use argent::utils::{calls::execute_multicall, test_dapp::TestDapp};
use starknet::{contract_address_const, deploy_syscall, account::Call};

#[test]
#[should_panic(expected: ('argent/multicall-failed', 0, 'CONTRACT_NOT_DEPLOYED'))]
fn execute_multicall_simple() {
    let call = Call { to: contract_address_const::<42>(), selector: 43, calldata: array![].span() };

    execute_multicall(array![call].span());
}

#[test]
#[should_panic(expected: ('argent/multicall-failed', 2, 'test dapp reverted', 'ENTRYPOINT_FAILED'))]
fn execute_multicall_at_one() {
    let class_hash = TestDapp::TEST_CLASS_HASH.try_into().unwrap();
    let (address0, _) = deploy_syscall(class_hash, 0, array![].span(), false).unwrap();

    let call1 = Call {
        to: address0,
        selector: 1257997212343903061729138261393903607425919870525153789348007715635666768741, // set_number(number)
        calldata: array![12].span()
    };

    let call2 = Call {
        to: address0,
        selector: 966438596990474552217413352546537164754794065595593730315125915414067970214, // increase_number(number)
        calldata: array![12].span()
    };

    let call3 = Call {
        to: address0,
        selector: 1378405772398747753825744346429351463310669626437442629621279049660910933566, // throw_error(number)
        calldata: array![12].span()
    };

    let arr = array![call1, call2, call3];
    execute_multicall(arr.span());
}

