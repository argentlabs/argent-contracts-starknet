use array::ArrayTrait;

use starknet::ContractAddress;
use starknet::SyscallResult;

use contracts::check_enough_gas;
use contracts::TestDapp;

fn call_contract_syscall(
    to: ContractAddress, selector: felt252, calldata: Array::<felt252>
) -> SyscallResult<Array::<felt252>> {
    check_enough_gas();
    if selector == 1 {
        TestDapp::set_number(*calldata.at(0_usize));
        SyscallResult::Ok(ArrayTrait::new())
    } else if selector == 2 {
        TestDapp::set_number_double(*calldata.at(0_usize));
        SyscallResult::Ok(ArrayTrait::new())
    } else if selector == 3 {
        TestDapp::set_number_times3(*calldata.at(0_usize));
        SyscallResult::Ok(ArrayTrait::new())
    } else if selector == 4 {
        let num = TestDapp::increase_number(*calldata.at(0_usize));
        let mut result = ArrayTrait::new();
        result.append(num);
        SyscallResult::Ok(result)
    } else if selector == 5 {
        // TestDapp::throw_error(*calldata.at(0_usize));
        let mut result = ArrayTrait::new();
        result.append('test dapp reverted');
        SyscallResult::Err(result)
    } else if selector == 6 {
        let num = TestDapp::get_number(to);
        let mut result = ArrayTrait::new();
        result.append(num);
        SyscallResult::Ok(result)
    } else {
        SyscallResult::Ok(calldata)
    }
}
