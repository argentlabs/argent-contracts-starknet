use contracts::Multicall;

#[test]
#[available_gas(20000)]
fn initialize() {
    let mut call_array = array_new::<felt>();
    let mut calldata = array_new::<felt>();
    assert(Multicall::aggregate(call_array, calldata) == 1, 'Value should be 1');
    
}

// from starkware.starknet.testing.starknet import Starknet
// from utils.utilities import compile, str_to_felt
// from utils.TransactionSender import from_call_to_call_array

// user1 = 0x69221ff9023c4d7ba9123f0f9c32634c23fc5776d86657f464ecb51fd811445
// user2 = 0x72648c3b1953572d2c4395a610f18b83cca14fa4d1ba10fc4484431fd463e5c


// async def test_multicall(starknet: Starknet):

//     multicall_cls = compile('contracts/lib/Multicall.cairo')
//     erc20_cls = compile('contracts/lib/ERC20.cairo')

//     multicall = await starknet.deploy(
//         contract_class=multicall_cls,
//         constructor_calldata=[]
//     )

//     erc20_1 = await starknet.deploy(
//         contract_class=erc20_cls,
//         constructor_calldata=[str_to_felt('token1'), str_to_felt('T1'), user1]
//     )

//     erc20_2 = await starknet.deploy(
//         contract_class=erc20_cls,
//         constructor_calldata=[str_to_felt('token2'), str_to_felt('T2'), user2]
//     )

//     call_array, calldata = from_call_to_call_array([
//         (erc20_1.contract_address, 'decimals', []),
//         (erc20_1.contract_address, 'balanceOf', [user1]),
//         (erc20_2.contract_address, 'balanceOf', [user2])
//     ])
//     response = await multicall.aggregate(call_array, calldata).call()

//     assert response.result.retdata == [
//             1, 18,       # 1st call result
//             2, 1000, 0,  # 2nd call result
//             2, 1000, 0   # 3rd call result
//     ]