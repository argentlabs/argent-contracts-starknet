import "dotenv/config";
import { declareContract, deployAccount, deployer, loadContract, provider } from "../tests-integration/lib";

const accountClassHash = await declareContract("ArgentAccount", true);
console.log("ArgentAccount class hash:", accountClassHash);
const testDappClassHash = await declareContract("TestDapp", true);
console.log("TestDapp class hash:", testDappClassHash);

console.log("Deploying new account");
const { account, owner, guardian } = await deployAccount({ classHash: accountClassHash });
console.log("Account address:", account.address);
console.log("Account owner private key:", owner.privateKey);
console.log("Account guardian private key:", guardian.privateKey);

console.log("Deploying new test dapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
console.log("TestDapp address:", contract_address);
const testDappContract = await loadContract(contract_address);

console.log("Calling test dapp");
testDappContract.connect(account);
const response = await testDappContract.set_number(42n);
await provider.waitForTransaction(response.transaction_hash);

const number = await testDappContract.get_number(account.address);
console.log(number === 42n ? "Seems good!" : "Something went wrong :(");
