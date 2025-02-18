import { readFileSync } from "fs";
import { json } from "starknet";

const contractsFolder = "./target/release/argent_";

function getContractSize(contractName: string): number {
  const compiledContract = json.parse(
    readFileSync(`${contractsFolder}${contractName}.compiled_contract_class.json`).toString("ascii"),
  );
  return compiledContract.bytecode.length;
}
// Max contract bytecode size at https://docs.starknet.io/chain-info/
console.log(`MAX SIZE:      81290`);
console.log(`Account Size:  ${getContractSize("ArgentAccount")}`);
console.log(`Multisig Size: ${getContractSize("ArgentMultisigAccount")}`);
