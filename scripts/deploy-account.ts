import "dotenv/config";
import { declareContract, deployAccount, deployer, loadContract, provider } from "../tests/lib";

const argentAccountClassHash = await declareContract("ArgentAccount");
console.log("ArgentAccount class hash:", argentAccountClassHash);

console.log("Deploying new account");
const wallet = await deployAccount(argentAccountClassHash);
const { account } = wallet;
console.log("Account address:", account.address);
console.log("Account owner private key:", wallet.owner.privateKey);
console.log("Account guardian private key:", wallet.guardian.privateKey);

const testDappClassHash = await declareContract("TestDapp");
console.log("TestDapp class hash:", testDappClassHash);
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
console.log("TestDapp address:", contract_address);
const testDappContract = await loadContract(contract_address);

testDappContract.connect(account);
const response = await testDappContract.set_number(42);
await provider.waitForTransaction(response.transaction_hash);

const number = await testDappContract.get_number(account.address);
console.log(number === 42n ? "Seems good!" : "Something went wrong :(");
