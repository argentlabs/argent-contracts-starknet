import "dotenv/config";
import { declareContract, deployer, deployMultisig, loadContract, provider } from "../lib";

const multisigClassHash = await declareContract("ArgentMultisig", true);
console.log("ArgentMultisig class hash:", multisigClassHash);
const mockDappClassHash = await declareContract("MockDapp", true);
console.log("MockDapp class hash:", mockDappClassHash);

console.log("Deploying new multisig");

const { account, keys } = await deployMultisig({
  threshold: 1,
  signersLength: 2,
  classHash: multisigClassHash,
});

console.log("Account address:", account.address);
console.log("Account keys:", keys);

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
