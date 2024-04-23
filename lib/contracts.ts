import { readFileSync } from "fs";
import {
  Abi,
  AccountInterface,
  CompiledSierra,
  Contract,
  DeclareContractPayload,
  ProviderInterface,
  RpcProvider,
  UniversalDeployerContractPayload,
  UniversalDetails,
  json,
} from "starknet";
import { Constructor } from ".";
import { deployer } from "./accounts";
import { provider } from "./provider";

export const contractsFolder = "./target/release/argent_";
export const fixturesFolder = "./tests-integration/fixtures/argent_";

export const WithContracts = <T extends Constructor<RpcProvider>>(Base: T) =>
  class extends Base {
    private classHashCache: Record<string, string> = {};

    removeFromCache(contractName: string) {
      delete this.classHashCache[contractName];
    }

    clearCache() {
      for (const contractName of Object.keys(this.classHashCache)) {
        delete this.classHashCache[contractName];
      }
    }

    // Could extends Account to add our specific fn but that's too early.
    async declareLocalContract(contractName: string, wait = true, folder = contractsFolder): Promise<string> {
      const cachedClass = this.classHashCache[contractName];
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
      this.classHashCache[contractName] = class_hash;
      return class_hash;
    }

    async declareFixtureContract(contractName: string, wait = true): Promise<string> {
      return await this.declareLocalContract(contractName, wait, fixturesFolder);
    }

    async loadContract(contractAddress: string, classHash?: string): Promise<ContractWithClassHash> {
      const { abi } = await provider.getClassAt(contractAddress);
      classHash ??= await provider.getClassHashAt(contractAddress);
      return new ContractWithClassHash(abi, contractAddress, provider, classHash);
    }

    async deployContract(
      contractName: string,
      payload: Omit<UniversalDeployerContractPayload, "classHash"> | UniversalDeployerContractPayload[] = {},
      details?: UniversalDetails,
      folder = contractsFolder,
    ): Promise<ContractWithClassHash> {
      const classHash = await this.declareLocalContract(contractName, true, folder);
      const { contract_address } = await deployer.deployContract({ ...payload, classHash }, details);

      // TODO could avoid network request and just create the contract using the ABI
      return await this.loadContract(contract_address, classHash);
    }
  };

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

export function getDeclareContractPayload(contractName: string, folder = contractsFolder): DeclareContractPayload {
  const contract: CompiledSierra = readContract(`${folder}${contractName}.contract_class.json`);
  const payload: DeclareContractPayload = { contract };
  if ("sierra_program" in contract) {
    payload.casm = readContract(`${folder}${contractName}.compiled_contract_class.json`);
  }
  return payload;
}

export function readContract(path: string) {
  return json.parse(readFileSync(path).toString("ascii"));
}
