import "dotenv/config";
import { deployAccount, deployer, manager } from "../lib";

const accountClassHash = await manager.declareLocalContract("ArgentAccount", true);
console.log("ArgentAccount class hash:", accountClassHash);
const mockDappClassHash = await manager.declareLocalContract("MockDapp", true);
console.log("MockDapp class hash:", mockDappClassHash);

console.log("Deploying new account");
// Deploy an account with 2 STRK
const { account } = await deployAccount({ classHash: accountClassHash, fundingAmount: 2 * 1e18 });
console.log("Account address:", account.address);

console.log("Deploying new test dapp");
const { contract_address } = await deployer.deployContract({ classHash: mockDappClassHash });
console.log("MockDapp address:", contract_address);
const mockDappContract = await manager.loadContract(contract_address);

console.log("Calling test dapp");
mockDappContract.providerOrAccount = account;
const response = await mockDappContract.set_number(42n);
await manager.waitForTx(response.transaction_hash);

const number = await mockDappContract.get_number(account.address);
console.log(number === 42n ? "Seems good!" : "Something went wrong :(");
