import "dotenv/config";
import { declareContract, deployer, deployMultisig, loadContract, provider } from "../tests/lib";

const multisigClassHash = await declareContract("ArgentMultisig", true);
console.log("ArgentMultisig class hash:", multisigClassHash);
const testDappClassHash = await declareContract("TestDapp", true);
console.log("TestDapp class hash:", testDappClassHash);

console.log("Deploying new account");

const threshold = 1;
const signersLength = 2;
const { account, keys, signers } = await deployMultisig(multisigClassHash, threshold, signersLength);

console.log("Account address:", account.address);
console.log("Account signers:", signers);
console.log(
  "Account private keys:",
  keys.map(({ privateKey }) => privateKey),
);

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
