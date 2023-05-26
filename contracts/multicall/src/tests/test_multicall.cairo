use array::{ArrayTrait, SpanTrait};

use starknet::contract_address_const;
use starknet::testing::{set_caller_address, set_block_number};

use lib::Call;
use lib::execute_multicall;
use multicall::aggregate;
use debug::PrintTrait;


#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/multicall-failed-', 0, 'CONTRACT_NOT_DEPLOYED'))]
fn execute_multicall_simple() {
    let call = Call {
        to: contract_address_const::<42>(), selector: 43, calldata: ArrayTrait::new()
    };

    let mut arr = ArrayTrait::new();
    arr.append(call);
    execute_multicall(arr.span());
}

