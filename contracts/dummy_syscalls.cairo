use starknet::ContractAddress;
use contracts::test_dapp::TestDapp;
use array::ArrayTrait;
use gas::get_gas_all;

fn call_contract(
    to: ContractAddress, selector: felt252, calldata: Array::<felt252>
) -> Array::<felt252> {
    match get_gas_all(get_builtin_costs()) {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            array_append(ref data, 'Out of gas');
            panic(data);
        },
    }
    if selector == 1 {
        TestDapp::set_number(*calldata.at(0_usize));
        ArrayTrait::new()
    } else if selector == 2 {
        TestDapp::set_number_double(*calldata.at(0_usize));
        ArrayTrait::new()
    } else if selector == 3 {
        TestDapp::set_number_times3(*calldata.at(0_usize));
        ArrayTrait::new()
    } else if selector == 4 {
        let num = TestDapp::increase_number(*calldata.at(0_usize));
        let mut arr = ArrayTrait::new();
        arr.append(num);
        arr
    } else if selector == 5 {
        TestDapp::throw_error(*calldata.at(0_usize));
        ArrayTrait::new()
    } else if selector == 6 {
        let num = TestDapp::get_number(to);
        let mut arr = ArrayTrait::new();
        arr.append(num);
        arr
    } else {
        calldata
    }
}
