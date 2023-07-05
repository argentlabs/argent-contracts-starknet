import "dotenv/config";
import { declareContract, deployAccount, deployer, loadContract, provider } from "../tests/lib";

// console.log("deployer nonce:", await provider.getNonceForAddress(deployer.address));
// console.log("deployer code:", await provider.getCode(deployer.address));

// const recipient = "42";
// const amount = uint256.bnToUint256(1);
// const ethContract = await getEthContract();
// console.log("ethContract:", ethContract);
// ethContract.connect(deployer);
// const { transaction_hash } = await ethContract.invoke("transfer", CallData.compile([recipient, 1, 0]));
// console.log("hash", transaction_hash);
// const receipt = await provider.waitForTransaction(transaction_hash);
// console.log("receipt", receipt);

// const first_retdata = [1];
// const { transaction_hash } = await ethContract.transfer(recipient, amount);
// console.log("hash:", transaction_hash);

const argentAccountClassHash = await declareContract("ArgentAccount", true);
// const argentAccountClassHash = "0x30d1ee3c42995c53c3d0bdc2ab448bdf7af64c2004e813ad4661b5be2565b8d";
console.log("ArgentAccount class hash:", argentAccountClassHash);

console.log("Deploying new account");
const { account } = await deployAccount(argentAccountClassHash);
console.log("Account address:", account.address);

const testDappClassHash = await declareContract("TestDapp");
// const testDappClassHash = "0x7ae203ced73744dfb1d40821ab4a6925b3b56bfab72e510933b7c02ab175b69";
console.log("TestDapp class hash:", testDappClassHash);
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
console.log("TestDapp address:", contract_address);
const testDappContract = await loadContract(contract_address);

testDappContract.connect(account);
const response = await testDappContract.set_number(42);
const receipt = await provider.waitForTransaction(response.transaction_hash);
console.log("receipt:", receipt);
