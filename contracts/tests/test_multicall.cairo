use array::ArrayTrait;
use array::SpanTrait;

use starknet::contract_address_const;
use starknet::testing::set_caller_address;
use starknet::testing::set_block_number;

use contracts::ArgentAccount::__execute__;
use contracts::Call;
use contracts::execute_multicall;
use contracts::aggregate;
use contracts::tests::initialize_account;

#[test]
#[available_gas(2000000)]
fn execute_multicall_simple() {
    let mut arr = ArrayTrait::new();
    arr.append(create_simple_call());
    arr.append(create_simple_call_with_data(43));
    let mut res = execute_multicall(arr);
    assert(res.len() == 2_usize, '2');
    assert(*res.at(0_usize) == 42, '42');
    assert(*res.at(1_usize) == 43, '43');
}

#[test]
#[available_gas(2000000)]
fn execute_multicall_test_dapp_1() {
    let mut arr = ArrayTrait::new();
    arr.append(create_set_number_call(12));
    arr.append(create_get_number_call());
    let retdata = execute_multicall(arr);
    assert(retdata.len() == 1_usize, '1');
    assert(*retdata.at(0_usize) == 12, '12');
}

#[test]
#[available_gas(2000000)]
fn execute_multicall_test_dapp_2() {
    let mut arr = ArrayTrait::new();
    arr.append(create_set_number_call_double(12));
    arr.append(create_get_number_call());
    arr.append(create_increase_number_call(18));
    arr.append(create_get_number_call());
    let retdata = execute_multicall(arr);
    assert(retdata.len() == 3_usize, '3');
    assert(*retdata.at(0_usize) == 24, '24');
    assert(*retdata.at(1_usize) == 42, '42 1');
    assert(*retdata.at(2_usize) == 42, '42 2');
}


#[test]
#[available_gas(2000000)]
fn execute_multicall_test_dapp_3() {
    let mut arr = ArrayTrait::new();
    arr.append(create_set_number_call(12));
    arr.append(create_get_number_call());
    arr.append(create_set_number_call_double(13));
    arr.append(create_get_number_call());
    arr.append(create_set_number_call_times3(14));
    arr.append(create_get_number_call());
    arr.append(create_increase_number_call(1));
    let retdata = execute_multicall(arr);
    assert(retdata.len() == 4_usize, '4');
    assert(*retdata.at(0_usize) == 12, '12');
    assert(*retdata.at(1_usize) == 26, '26');
    assert(*retdata.at(2_usize) == 42, '42');
    assert(*retdata.at(3_usize) == 43, '43');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/multicall-failed-', 1))]
fn execute_multicall_test_dapp_with_create_throw_error_call() {
    let mut arr = ArrayTrait::new();
    arr.append(create_set_number_call(12));
    arr.append(create_throw_error_call(12));
    arr.append(create_get_number_call());
    let retdata = execute_multicall(arr);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/multicall-failed-', 0))]
fn execute_multicall_test_dapp_with_create_throw_error_call_beginning() {
    let mut arr = ArrayTrait::new();
    arr.append(create_throw_error_call(12));
    arr.append(create_set_number_call(12));
    arr.append(create_get_number_call());
    let retdata = execute_multicall(arr);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/multicall-failed-', 2))]
fn execute_multicall_test_dapp_with_create_throw_error_call_end() {
    let mut arr = ArrayTrait::new();
    arr.append(create_set_number_call(12));
    arr.append(create_get_number_call());
    arr.append(create_throw_error_call(12));
    let retdata = execute_multicall(arr);
}

#[test]
#[available_gas(2000000)]
fn aggregate_simple() {
    let mut arr = ArrayTrait::new();
    arr.append(create_simple_call());
    arr.append(create_simple_call_with_data(43));
    set_block_number(42_u64);
    let (block_number, retdata) = aggregate(arr);
    assert(block_number == 42_u64, 'Block number should 42');
    assert(retdata.len() == 2_usize, '2');
    assert(*retdata.at(0_usize) == 42, '42');
    assert(*retdata.at(1_usize) == 43, '43');
}

// __execute__
#[test]
#[available_gas(2000000)]
fn execute() {
    let mut arr = ArrayTrait::<Call>::new();
    arr.append(create_simple_call());
    arr.append(create_simple_call_with_data(43));
    let retdata = __execute__(arr);
    assert(retdata.len() == 2_usize, '2');
    assert(*retdata.at(0_usize) == 42, '42');
    assert(*retdata.at(1_usize) == 43, '43');
}

// TODO can't mock tx_version atm so dummy test
// #[test]
// #[available_gas(2000000)]
// // #[should_panic(expected = ('argent/only-self', ))]
// fn execute_assert_correct_tx_version() {
//     initialize_account();
//     set_tx_version(1);
//     __execute__(ArrayTrait::new());
// }

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/no-reentrant-call', ))]
fn execute_assert_non_reentrant() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    __execute__(ArrayTrait::new());
}

fn create_simple_call() -> Call {
    create_call_with(42, 42)
}

fn create_simple_call_with_data(number: felt252) -> Call {
    create_call_with(42, number)
}


fn create_set_number_call(number: felt252) -> Call {
    create_call_with(1, number)
}

fn create_set_number_call_double(number: felt252) -> Call {
    create_call_with(2, number)
}

fn create_set_number_call_times3(number: felt252) -> Call {
    create_call_with(3, number)
}

fn create_increase_number_call(number: felt252) -> Call {
    create_call_with(4, number)
}

fn create_throw_error_call(number: felt252) -> Call {
    create_call_with(5, number)
}

fn create_get_number_call() -> Call {
    create_call_with(6, 0)
}

fn create_call_with(selector: felt252, data: felt252) -> Call {
    let mut calldata = ArrayTrait::new();
    calldata.append(data);
    let to = contract_address_const::<0>();
    Call { to, selector, calldata }
}
