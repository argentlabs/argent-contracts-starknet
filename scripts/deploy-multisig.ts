import "dotenv/config";
import { deployer, deployMultisig, manager } from "../lib";

const multisigClassHash = await manager.declareLocalContract("ArgentMultisigAccount", true);
console.log("ArgentMultisig class hash:", multisigClassHash);
const mockDappClassHash = await manager.declareLocalContract("MockDapp", true);
console.log("MockDapp class hash:", mockDappClassHash);

console.log("Deploying new multisig");

const { account, keys } = await deployMultisig({
  threshold: 1,
  signersLength: 2,
  classHash: multisigClassHash,
  fundingAmount: 0.0002 * 1e18,
  useTxV3: false,
});

console.log("Account address:", account.address);
console.log("Account keys:", keys);

console.log("Deploying new test dapp");
const { contract_address } = await deployer.deployContract({ classHash: mockDappClassHash });
console.log("MockDapp address:", contract_address);
const mockDappContract = await manager.loadContract(contract_address);

console.log("Calling test dapp");
mockDappContract.connect(account);
const response = await mockDappContract.set_number(42n);
await manager.waitToResolveTransaction(response.transaction_hash);

const number = await mockDappContract.get_number(account.address);
console.log(number === 42n ? "Seems good!" : "Something went wrong :(");
