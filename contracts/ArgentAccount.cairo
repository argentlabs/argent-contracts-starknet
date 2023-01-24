#[contract]
mod ArgentAccount {
    #[view]
    fn supports_interface(interface_id: felt) -> bool {
        if interface_id == 0x01ffc9a7 { // ERC165
            true
        } else if interface_id == 0x12456789 { // TODO: IAccount interface id
            true
        } else {
            false
        }
    }
}

fn single_element_arr(value: felt) -> Array::<felt> {
    let mut arr = array_new::<felt>();
    array_append::<felt>(ref arr, value);
    arr
}

fn pop_and_compare(ref arr: Array::<felt>, value: felt, err: felt) {
    match array_pop_front::<felt>(ref arr) {
        Option::Some(x) => {
            assert(x == value, err);
        },
        Option::None(_) => {
            panic(single_element_arr('Got empty result data'))
        },
    };
}

fn assert_empty(mut arr: Array::<felt>) {
    assert(array_len::<felt>(ref arr) == 0_u128, 'Array not empty');
}


#[test]
#[available_gas(20000)]
fn test_supported_interfaces() {
    let mut retdata = ArgentAccount::__external::supports_interface(single_element_arr(0x01ffc9a7));
    pop_and_compare(ref retdata, 1, 'Wrong result');
    assert_empty(retdata);
}

#[test]
#[available_gas(20000)]
fn test_unsupported_interface() {
    let mut retdata = ArgentAccount::__external::supports_interface(single_element_arr(0));
    pop_and_compare(ref retdata, 0, 'Wrong result');
    assert_empty(retdata);

    retdata = ArgentAccount::__external::supports_interface(single_element_arr(69));
    pop_and_compare(ref retdata, 0, 'Wrong result');
    assert_empty(retdata);
}

