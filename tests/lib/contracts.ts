import { readFileSync } from "fs";
import { CompiledSierra, CompiledSierraCasm, Contract, DeclareContractPayload, json } from "starknet";
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
export async function declareContract(contractName: string): Promise<string> {
  console.log(`\tDeclaring ${contractName}...`);
  const cachedClass = classHashCache[contractName];
  if (cachedClass) {
    return cachedClass;
  }
  const contract: CompiledSierra = json.parse(
    readFileSync(`${contractsFolder}${contractsPrefix}${contractName}.sierra.json`).toString("ascii"),
  );
  let returnedClashHash;
  if ("sierra_program" in contract) {
    const casm: CompiledSierraCasm = json.parse(
      readFileSync(`${contractsFolder}${contractsPrefix}${contractName}.casm.json`).toString("ascii"),
    );
    returnedClashHash = await actualDeclare({ contract, casm });
  } else {
    returnedClashHash = await actualDeclare({ contract });
  }
  classHashCache[contractName] = returnedClashHash;
  return returnedClashHash;
}

async function actualDeclare(payload: DeclareContractPayload): Promise<string> {
  const { class_hash } = await deployer.declareIfNot(payload, { maxFee: 1e18 }); // max fee avoids slow estimate
  return class_hash;
}

export async function loadContract(contract_address: string) {
  const { abi: testAbi } = await provider.getClassAt(contract_address);
  if (!testAbi) {
    throw new Error("Error while getting ABI");
  }
  // TODO WARNING THIS IS A TEMPORARY FIX WHILE WE WAIT FOR SNJS TO BE UPDATED
  // Allows to pull back the function from one level down
  const parsedAbi = testAbi.flatMap((e) => {
    if (e.type == "interface") {
      return e.items;
    } else {
      return e;
    }
  });
  return new Contract(parsedAbi, contract_address, provider);
}
