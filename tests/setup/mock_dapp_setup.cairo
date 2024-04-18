use argent::mocks::mock_dapp::IMockDappDispatcher;
use snforge_std::{declare, ContractClassTrait, ContractClass};
use super::constants::MOCK_DAPP_ADDRESS;


fn initialize_mock_dapp() -> IMockDappDispatcher {
    let calldata = array![];
    let contract = declare("MockDapp");
    let contract_address = contract
        .deploy_at(@calldata, MOCK_DAPP_ADDRESS.try_into().unwrap())
        .expect('Failed to deploy Mock Dapp');

    IMockDappDispatcher { contract_address }
}
