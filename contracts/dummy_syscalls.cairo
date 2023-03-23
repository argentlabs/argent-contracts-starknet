use array::ArrayTrait;
use array::SpanTrait;

use starknet::ContractAddress;
use starknet::SyscallResult;

use contracts::check_enough_gas;
use contracts::TestDapp;

fn call_contract_syscall(
    to: ContractAddress, selector: felt252, calldata: Span::<felt252>
) -> SyscallResult<Span::<felt252>> {
    check_enough_gas();
    if selector == 1 {
        TestDapp::set_number(*calldata.at(0_usize));
        empty_restult()
    } else if selector == 2 {
        TestDapp::set_number_double(*calldata.at(0_usize));
        empty_restult()
    } else if selector == 3 {
        TestDapp::set_number_times3(*calldata.at(0_usize));
        empty_restult()
    } else if selector == 4 {
        let num = TestDapp::increase_number(*calldata.at(0_usize));
        let mut result = ArrayTrait::new();
        result.append(num);
        SyscallResult::Ok(result.span())
    } else if selector == 5 {
        // TestDapp::throw_error(*calldata.at(0_usize));
        let mut result = ArrayTrait::new();
        result.append('test dapp reverted');
        SyscallResult::Err(result)
    } else if selector == 6 {
        let num = TestDapp::get_number(to);
        let mut result = ArrayTrait::new();
        result.append(num);
        SyscallResult::Ok(result.span())
    } else {
        SyscallResult::Ok(calldata)
    }
}

fn empty_restult() -> SyscallResult<Span::<felt252>> {
    SyscallResult::Ok(ArrayTrait::new().span())
}
