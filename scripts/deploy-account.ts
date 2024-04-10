import "dotenv/config";
import { declareContract, deployAccount, deployer, loadContract, provider } from "../lib";

const accountClassHash = await declareContract("ArgentAccount", true);
console.log("ArgentAccount class hash:", accountClassHash);
const mockDappClassHash = await declareContract("MockDapp", true);
console.log("MockDapp class hash:", mockDappClassHash);

console.log("Deploying new account");
const { account } = await deployAccount({ classHash: accountClassHash });
console.log("Account address:", account.address);

console.log("Deploying new test dapp");
const { contract_address } = await deployer.deployContract({ classHash: mockDappClassHash });
console.log("MockDapp address:", contract_address);
const mockDappContract = await loadContract(contract_address);

console.log("Calling test dapp");
mockDappContract.connect(account);
const response = await mockDappContract.set_number(42n);
await provider.waitForTransaction(response.transaction_hash);

const number = await mockDappContract.get_number(account.address);
console.log(number === 42n ? "Seems good!" : "Something went wrong :(");
