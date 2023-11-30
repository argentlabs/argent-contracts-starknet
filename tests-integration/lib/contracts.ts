import { readFileSync } from "fs";
import { CompiledSierra, Contract, DeclareContractPayload, json, num, uint256 } from "starknet";
import { deployer } from "./accounts";
import { provider } from "./provider";

const classHashCache: Record<string, string> = {};

export const ethAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7";
let ethContract: Contract;

export const contractsFolder = "./target/release/argent_";
export const fixturesFolder = "./tests-integration/fixtures/argent_";

export async function getEthContract() {
  if (ethContract) {
    return ethContract;
  }
  const ethProxy = await loadContract(ethAddress);
  const implementationAddress = num.toHex((await ethProxy.implementation()).address);
  const ethImplementation = await loadContract(implementationAddress);
  ethContract = new Contract(ethImplementation.abi, ethAddress, ethProxy.providerOrAccount);
  return ethContract;
}

export async function getEthBalance(accountAddress: string): Promise<bigint> {
  const ethContract = await getEthContract();
  return uint256.uint256ToBN((await ethContract.balanceOf(accountAddress)).balance);
}

export function removeFromCache(contractName: string) {
  delete classHashCache[contractName];
}

// Could extends Account to add our specific fn but that's too early.
export async function declareContract(contractName: string, wait = true, folder = contractsFolder): Promise<string> {
  const cachedClass = classHashCache[contractName];
  if (cachedClass) {
    return cachedClass;
  }
  const contract: CompiledSierra = readContract(`${folder}${contractName}.contract_class.json`);
  const payload: DeclareContractPayload = { contract };
  if ("sierra_program" in contract) {
    payload.casm = readContract(`${folder}${contractName}.compiled_contract_class.json`);
  }
  const skipSimulation = provider.isDevnet;
  const maxFee = skipSimulation ? 1e18 : undefined;
  const { class_hash, transaction_hash } = await deployer.declareIfNot(payload, { maxFee }); // max fee avoids slow estimate
  if (wait && transaction_hash) {
    await provider.waitForTransaction(transaction_hash);
    console.log(`\t${contractName} declared`);
  }
  classHashCache[contractName] = class_hash;
  return class_hash;
}

export async function declareFixtureContract(contractName: string, wait = true): Promise<string> {
  return await declareContract(contractName, wait, fixturesFolder);
}

export async function loadContract(contractAddress: string) {
  const { abi } = await provider.getClassAt(contractAddress);
  if (!abi) {
    throw new Error("Error while getting ABI");
  }
  // TODO WARNING THIS IS A TEMPORARY FIX WHILE WE WAIT FOR SNJS TO BE UPDATED
  // Allows to pull back the function from one level down
  const parsedAbi = abi.flatMap((e) => (e.type == "interface" ? e.items : e));
  return new Contract(parsedAbi, contractAddress, provider);
}

export function readContract(path: string) {
  return json.parse(readFileSync(path).toString("ascii"));
}
