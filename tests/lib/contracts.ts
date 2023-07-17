import { readFileSync } from "fs";
import { CompiledSierra, Contract, DeclareContractPayload, json } from "starknet";
import { deployer } from "./accounts";
import { provider } from "./provider";

const classHashCache: Record<string, string> = {};

export const ethAddress = "0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7";
let ethContract: Contract;

export const contractsFolder = "./target/dev/";
export const contractsPrefix = "argent_contracts_";

export async function getEthContract() {
  if (ethContract) {
    return ethContract;
  }
  ethContract = await loadContract(ethAddress);
  return ethContract;
}

export function removeFromCache(contractName: string) {
  delete classHashCache[contractName];
}

// Could extends Account to add our specific fn but that's too early.
export async function declareContract(contractName: string, wait = true): Promise<string> {
  const cachedClass = classHashCache[contractName];
  if (cachedClass) {
    return cachedClass;
  }
  const contract: CompiledSierra = json.parse(
    readFileSync(`${contractsFolder}${contractsPrefix}${contractName}.sierra.json`).toString("ascii"),
  );
  const payload: DeclareContractPayload = { contract };
  if ("sierra_program" in contract) {
    payload.casm = json.parse(
      readFileSync(`${contractsFolder}${contractsPrefix}${contractName}.casm.json`).toString("ascii"),
    );
  }
  const { class_hash, transaction_hash } = await deployer.declareIfNot(payload, { maxFee: 1e18 }); // max fee avoids slow estimate
  if (wait && transaction_hash) {
    await provider.waitForTransaction(transaction_hash);
    console.log(`\t${contractName} declared`);
  }
  classHashCache[contractName] = class_hash;
  return class_hash;
}

export async function loadContract(contract_address: string) {
  const { abi } = await provider.getClassAt(contract_address);
  if (!abi) {
    throw new Error("Error while getting ABI");
  }
  // TODO WARNING THIS IS A TEMPORARY FIX WHILE WE WAIT FOR SNJS TO BE UPDATED
  // Allows to pull back the function from one level down
  const parsedAbi = abi.flatMap((e) => (e.type == "interface" ? e.items : e));
  return new Contract(parsedAbi, contract_address, provider);
}
