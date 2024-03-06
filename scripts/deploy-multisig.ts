import "dotenv/config";
import { declareContract, deployer, deployMultisig, loadContract, provider } from "../tests-integration/lib";

const multisigClassHash = await declareContract("ArgentMultisig", true);
console.log("ArgentMultisig class hash:", multisigClassHash);
const testDappClassHash = await declareContract("TestDapp", true);
console.log("TestDapp class hash:", testDappClassHash);

console.log("Deploying new multisig");

const { account, signers } = await deployMultisig({
  threshold: 1,
  signersLength: 2,
  classHash: multisigClassHash,
});

console.log("Account address:", account.address);
console.log("Account signers:", signers);

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
