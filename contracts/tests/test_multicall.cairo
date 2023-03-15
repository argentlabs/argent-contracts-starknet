use array::ArrayTrait;

use starknet::contract_address_const;
use starknet::testing::set_caller_address;
use starknet::testing::set_block_number;

use contracts::execute_multicall;
use contracts::Call;

impl ArrayCallDrop of Drop::<Array::<Call>>;

#[test]
#[available_gas(2000000)]
fn execute_multicall_simple() {
    let mut arr = array_new::<Call>();
    arr.append(get_call());
    arr.append(get_call_with_data(43));
    let mut res = execute_multicall(arr);
    assert(res.len() == 2_usize, '2');
    assert(*res.at(0_usize) == 42, '42');
    assert(*res.at(1_usize) == 43, '43');
}

#[test]
#[available_gas(2000000)]
fn execute_multicall_test_dapp_1() {
    let mut arr = array_new::<Call>();
    arr.append(set_number(12));
    arr.append(get_number());
    let retdata = execute_multicall(arr);
    assert(retdata.len() == 1_usize, '1');
    assert(*retdata.at(0_usize) == 12, '12');
}

#[test]
#[available_gas(2000000)]
fn execute_multicall_test_dapp_2() {
    let mut arr = array_new::<Call>();
    arr.append(set_number_double(12));
    arr.append(get_number());
    arr.append(increase_number(18));
    arr.append(get_number());
    let retdata = execute_multicall(arr);
    assert(retdata.len() == 3_usize, '3');
    assert(*retdata.at(0_usize) == 24, '24');
    assert(*retdata.at(1_usize) == 42, '42 1');
    assert(*retdata.at(2_usize) == 42, '42 2');
}


#[test]
#[available_gas(2000000)]
fn execute_multicall_test_dapp_3() {
    let mut arr = array_new::<Call>();
    arr.append(set_number(12));
    arr.append(get_number());
    arr.append(set_number_double(13));
    arr.append(get_number());
    arr.append(set_number_times3(14));
    arr.append(get_number());
    arr.append(increase_number(1));
    let retdata = execute_multicall(arr);
    assert(retdata.len() == 4_usize, '4');
    assert(*retdata.at(0_usize) == 12, '12');
    assert(*retdata.at(1_usize) == 26, '26');
    assert(*retdata.at(2_usize) == 42, '42');
    assert(*retdata.at(3_usize) == 43, '43');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('test dapp reverted', ))]
fn execute_multicall_test_dapp_with_throw_error() {
    let mut arr = array_new::<Call>();
    arr.append(set_number(12));
    arr.append(throw_error(12));
    arr.append(get_number());
    let retdata = execute_multicall(arr);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('test dapp reverted', ))]
fn execute_multicall_test_dapp_with_throw_error_beginning() {
    let mut arr = array_new::<Call>();
    arr.append(throw_error(12));
    arr.append(set_number(12));
    arr.append(get_number());
    let retdata = execute_multicall(arr);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('test dapp reverted', ))]
fn execute_multicall_test_dapp_with_throw_error_end() {
    let mut arr = array_new::<Call>();
    arr.append(set_number(12));
    arr.append(get_number());
    arr.append(throw_error(12));
    let retdata = execute_multicall(arr);
}


// #[test]
// #[available_gas(2000000)]
// fn aggregate() {
//     let mut arr = array_new::<Call>();
//     arr.append(get_call());
//     arr.append(get_call_with_data(43));
//     set_block_number(42_u64);
//     let (block_number, retdata) = aggregate(arr);
//     assert(block_number == 42_u64, 'Block number should 42');
//     assert(retdata.len() == 2_usize, '2');
//     assert(*retdata.at(0_usize) == 42, '42');
//     assert(*retdata.at(1_usize) == 43, '43');
// }

fn get_call() -> Call {
    create_call_with(42, 42)
}

fn get_call_with_data(number: felt252) -> Call {
    create_call_with(42, number)
}


fn set_number(number: felt252) -> Call {
    create_call_with(1, number)
}

fn set_number_double(number: felt252) -> Call {
    create_call_with(2, number)
}

fn set_number_times3(number: felt252) -> Call {
    create_call_with(3, number)
}

fn increase_number(number: felt252) -> Call {
    create_call_with(4, number)
}

fn throw_error(number: felt252) -> Call {
    create_call_with(5, number)
}

fn get_number() -> Call {
    create_call_with(6, 0)
}

fn create_call_with(selector: felt252, data: felt252) -> Call {
    let mut calldata = ArrayTrait::new();
    calldata.append(data);
    let to = contract_address_const::<0>();
    Call { to, selector, calldata }
}
