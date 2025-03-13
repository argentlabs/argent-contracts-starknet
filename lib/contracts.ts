import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "fs";
import { dirname, resolve } from "path";
import {
  Abi,
  AccountInterface,
  CompiledSierra,
  Contract,
  DeclareContractPayload,
  ProviderInterface,
  UniversalDetails,
  extractContractHashes,
  json,
} from "starknet";
import { deployer } from "./accounts";
import { WithDevnet } from "./devnet";

export const contractsFolder = "./target/release/argent_";
export const fixturesFolder = "./tests-integration/fixtures/argent_";
const artifactsFolder = "./deployments/artifacts";
const cacheClassHashFilepath = "./dist/classHashCache.json";

export const WithContracts = <T extends ReturnType<typeof WithDevnet>>(Base: T) =>
  class extends Base {
    // Maps a contract name to its class hash to avoid redeclaring the same contract
    protected declaredContracts: Record<string, string> = {};
    // Holds the latest know class hashes for a given contract
    // It doesn't guarantee that the class hash is up to date, or that the contacts is declared
    protected cacheClassHashes: Record<string, { compiledClassHash: string | undefined; classHash: string }> = {};

    clearClassCache() {
      for (const contractName of Object.keys(this.declaredContracts)) {
        delete this.declaredContracts[contractName];
      }
    }

    async restartDevnetAndClearClassCache() {
      if (this.isDevnet) {
        await this.restart();
        this.clearClassCache();
      }
    }

    // Could extends Account to add our specific fn but that's too early.
    async declareLocalContract(contractName: string, wait = true, folder = contractsFolder): Promise<string> {
      const cachedClass = this.declaredContracts[contractName];
      if (cachedClass) {
        return cachedClass;
      }

      const payload = getDeclareContractPayload(contractName, folder);
      let details: UniversalDetails | undefined;
      // Setting resourceBounds skips estimate
      if (this.isDevnet) {
        details = {
          skipValidate: true,
          resourceBounds: {
            l2_gas: { max_amount: "0x0", max_price_per_unit: "0x0" },
            l1_gas: { max_amount: "0x30000", max_price_per_unit: "0x300000000000" },
          },
        };
      }
      try {
        return await this.declareIfNotAndCache(contractName, payload, details, wait);
      } catch (e: any) {
        if (e.toString().includes("the compiled class hash did not match the one supplied in the transaction")) {
          // Remove from cache
          delete this.cacheClassHashes[contractName];
          return await this.declareIfNotAndCache(contractName, payload, details, wait);
        }
        throw e;
      }
    }

    async declareIfNotAndCache(
      contractName: string,
      payload: DeclareContractPayload,
      details?: UniversalDetails,
      wait = true,
    ) {
      // If cache isn't initialized, initialize it
      if (Object.keys(this.cacheClassHashes).length === 0) {
        if (!existsSync(cacheClassHashFilepath)) {
          mkdirSync(dirname(cacheClassHashFilepath), { recursive: true });
          writeFileSync(cacheClassHashFilepath, "{}");
        }

        this.cacheClassHashes = JSON.parse(readFileSync(cacheClassHashFilepath).toString("ascii"));
      }

      // If the contract is not in the cache, extract the class hash and add it to the cache
      if (!this.cacheClassHashes[contractName]) {
        const { compiledClassHash, classHash } = extractContractHashes(payload);
        this.cacheClassHashes[contractName] = { compiledClassHash, classHash };
        console.log(`Updating cache for ${contractName}`);
        writeFileSync(cacheClassHashFilepath, JSON.stringify(this.cacheClassHashes, null, 2));
      }
      // Populate the payload with the class hash
      payload.compiledClassHash = this.cacheClassHashes[contractName].compiledClassHash;
      payload.classHash = this.cacheClassHashes[contractName].classHash;

      const { class_hash, transaction_hash } = await deployer.declareIfNot(payload, details);
      if (wait && transaction_hash) {
        await this.waitForTransaction(transaction_hash);
        console.log(`\t${contractName} declared`);
      }
      this.declaredContracts[contractName] = class_hash;
      return class_hash;
    }

    async declareFixtureContract(contractName: string, wait = true): Promise<string> {
      return await this.declareLocalContract(contractName, wait, fixturesFolder);
    }

    async declareArtifactAccountContract(contractVersion: string, wait = true): Promise<string> {
      const allArtifactsFolders = getSubfolders(artifactsFolder);
      let contractName = allArtifactsFolders.find((folder) => folder.startsWith(`account-${contractVersion}`));
      if (!contractName) {
        throw new Error(`No contract found for version ${contractVersion}`);
      }
      contractName = `/${contractName}/ArgentAccount`;
      return await this.declareLocalContract(contractName, wait, artifactsFolder);
    }

    async declareArtifactMultisigContract(contractVersion: string, wait = true): Promise<string> {
      const allArtifactsFolders = getSubfolders(artifactsFolder);
      let contractName = allArtifactsFolders.find((folder) => folder.startsWith(`multisig-${contractVersion}`));
      if (!contractName) {
        throw new Error(`No contract found for version ${contractVersion}`);
      }
      contractName = `/${contractName}/ArgentMultisig`;
      return await this.declareLocalContract(contractName, wait, artifactsFolder);
    }

    async loadContract(contractAddress: string, classHash?: string): Promise<ContractWithClass> {
      const { abi } = await this.getClassAt(contractAddress);
      classHash ??= await this.getClassHashAt(contractAddress);
      return new ContractWithClass(abi, contractAddress, this, classHash);
    }

    async declareAndDeployContract(contractName: string): Promise<ContractWithClass> {
      const classHash = await this.declareLocalContract(contractName, true, contractsFolder);
      const { contract_address } = await deployer.deployContract({ classHash });

      // TODO could avoid network request and just create the contract using the ABI
      return await this.loadContract(contract_address, classHash);
    }
  };

export class ContractWithClass extends Contract {
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

/**
 * Get all subfolders in a directory.
 * @param dirPath The directory path to search.
 * @returns An array of subfolder names.
 */
function getSubfolders(dirPath: string): string[] {
  try {
    // Resolve the directory path to an absolute path
    const absolutePath = resolve(dirPath);

    // Read all items in the directory
    const items = readdirSync(absolutePath, { withFileTypes: true });

    // Filter for directories and map to their names
    const folders = items.filter((item) => item.isDirectory()).map((folder) => folder.name);

    return folders;
  } catch (err) {
    throw new Error(`Error reading the directory at ${dirPath}`);
  }
}
