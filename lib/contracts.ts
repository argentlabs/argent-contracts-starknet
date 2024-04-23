import { readFileSync } from "fs";
import {
  Abi,
  AccountInterface,
  CompiledSierra,
  Contract,
  DeclareContractPayload,
  ProviderInterface,
  UniversalDeployerContractPayload,
  UniversalDetails,
  json,
} from "starknet";
import { deployer } from "./accounts";
import { provider } from "./provider";

const classHashCache: Record<string, string> = {};

export const contractsFolder = "./target/release/argent_";
export const fixturesFolder = "./tests-integration/fixtures/argent_";

export class ContractWithClassHash extends Contract {
  constructor(
    abi: Abi,
    address: string,
    providerOrAccount: ProviderInterface | AccountInterface,
    public readonly classHash: string,
  ) {
    super(abi, address, providerOrAccount);
  }
}

export function removeFromCache(contractName: string) {
  delete classHashCache[contractName];
}

export function clearCache() {
  Object.keys(classHashCache).forEach((key) => delete classHashCache[key]);
}

export function getDeclareContractPayload(contractName: string, folder = contractsFolder): DeclareContractPayload {
  const contract: CompiledSierra = readContract(`${folder}${contractName}.contract_class.json`);
  const payload: DeclareContractPayload = { contract };
  if ("sierra_program" in contract) {
    payload.casm = readContract(`${folder}${contractName}.compiled_contract_class.json`);
  }
  return payload;
}

// Could extends Account to add our specific fn but that's too early.
export async function declareContract(contractName: string, wait = true, folder = contractsFolder): Promise<string> {
  const cachedClass = classHashCache[contractName];
  if (cachedClass) {
    return cachedClass;
  }
  const payload = getDeclareContractPayload(contractName, folder);
  const skipSimulation = provider.isDevnet;
  // max fee avoids slow estimate
  const maxFee = skipSimulation ? 1e18 : undefined;

  const { class_hash, transaction_hash } = await deployer.declareIfNot(payload, { maxFee });

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

export async function loadContract(contractAddress: string, classHash?: string): Promise<ContractWithClassHash> {
  const { abi } = await provider.getClassAt(contractAddress);
  if (!abi) {
    throw new Error("Error while getting ABI");
  }

  return new ContractWithClassHash(
    abi,
    contractAddress,
    provider,
    classHash ?? (await provider.getClassHashAt(contractAddress)),
  );
}

export function readContract(path: string) {
  return json.parse(readFileSync(path).toString("ascii"));
}

export async function deployContract(
  contractName: string,
  payload: Omit<UniversalDeployerContractPayload, "classHash"> | UniversalDeployerContractPayload[] = {},
  details?: UniversalDetails,
  folder = contractsFolder,
): Promise<ContractWithClassHash> {
  const declaredClassHash = await declareContract(contractName, true, folder);
  const { contract_address } = await deployer.deployContract({ ...payload, classHash: declaredClassHash }, details);

  // TODO could avoid network request and just create the contract using the ABI
  return await loadContract(contract_address, declaredClassHash);
}
