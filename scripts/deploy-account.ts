import "dotenv/config";
import { Account, constants } from "starknet";
import { FastProvider, declareContract, deployAccount, loadContract, provider } from "../tests/lib";

const address = process.env.ADDRESS as string;
const privateKey = process.env.PRIVATE_KEY as string;
const deployer = new Account(provider, address, privateKey);

console.log("deployer address:", deployer.address);

// console.log("deployer nonce:", await provider.getNonceForAddress(deployer.address));
// console.log("deployer code:", await provider.getCode(deployer.address));

const argentAccountClassHash = await declareContract("ArgentAccount", true);
// const argentAccountClassHash = "0x7d297762e06d3c29c9d66a8c72379c4486d3aa7c1ea8beeb11732ca795c8cc6";
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
