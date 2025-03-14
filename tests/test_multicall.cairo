use argent::utils::calls::execute_multicall;
use core::traits::TryInto;
use snforge_std::{ContractClass, ContractClassTrait, DeclareResult, declare};
use starknet::account::Call;

// failing test for now
// As execute doesn't return a result, we cannot catch the 'call_contract_syscall' error
// "While the Cairo test runner propagates errors to the calling
// contract when safe dispatchers are used, the non-panicking behavior
// will not be observed on Starknet itself! The production systems (Starknet Testnet or Mainnet)
// do not yet support graceful failure in internal calls. If an inner call panics, the entire
// transaction immediately reverts. This will change in the future,"
// #[test]
// #[should_panic(expected: ('argent/multicall-failed', 0, 'CONTRACT_NOT_DEPLOYED'))]
// fn execute_multicall_simple() {
//     let call = Call { to: 42.try_into().unwrap(), selector: 43, calldata: array![].span() };
//     execute_multicall(array![call].span());
// }

#[test]
#[should_panic(expected: ('argent/multicall-failed', 2, 'test dapp reverted'))]
fn execute_multicall_at_one() {
    let declare_result = declare("MockDapp");
    let contract_class = match declare_result {
        Result::Ok(declare_result) => match declare_result {
            DeclareResult::Success(contract_class) => contract_class,
            DeclareResult::AlreadyDeclared(contract_class) => contract_class,
        },
        Result::Err(_) => panic_with_felt252('err declaring ArgentAccount'),
    };

    let constructor = array![];
    let (contract_address, _) = contract_class.deploy(@constructor).expect('Failed to deploy contract');

    let call1 = Call {
        to: contract_address,
        selector: 1257997212343903061729138261393903607425919870525153789348007715635666768741, // set_number(number)
        calldata: array![12].span(),
    };

    let call2 = Call {
        to: contract_address,
        selector: 966438596990474552217413352546537164754794065595593730315125915414067970214, // increase_number(number)
        calldata: array![12].span(),
    };

    let call3 = Call {
        to: contract_address,
        selector: 1378405772398747753825744346429351463310669626437442629621279049660910933566, // throw_error(number)
        calldata: array![12].span(),
    };

    let arr = array![call1, call2, call3];
    execute_multicall(arr.span());
}
