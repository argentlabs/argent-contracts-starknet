import { readFileSync, readdirSync } from "fs";
import { resolve } from "path";
import {
  Abi,
  AccountInterface,
  CompiledSierra,
  Contract,
  DeclareContractPayload,
  ProviderInterface,
  UniversalDetails,
  json,
} from "starknet";
import { deployer } from "./accounts";
import { WithDevnet } from "./devnet";

export const contractsFolder = "./target/release/argent_";
export const fixturesFolder = "./tests-integration/fixtures/argent_";
const artifactsFolder = "./deployments/artifacts";

export const WithContracts = <T extends ReturnType<typeof WithDevnet>>(Base: T) =>
  class extends Base {
    protected classCache: Record<string, string> = {};

    removeFromClassCache(contractName: string) {
      delete this.classCache[contractName];
    }

    clearClassCache() {
      for (const contractName of Object.keys(this.classCache)) {
        delete this.classCache[contractName];
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
      const cachedClass = this.classCache[contractName];
      if (cachedClass) {
        return cachedClass;
      }
      const payload = getDeclareContractPayload(contractName, folder);
      let details: UniversalDetails | undefined;
      // Setting resourceBounds skips estimate
      if (this.isDevnet) {
      console.log("PRE");
      console.log(payload);
      populatePayloadWithClassHashes(payload, contractName);
      console.log("POST");
      console.log(payload);
      details = {
          skipValidate: true,
          resourceBounds: {
            l2_gas: { max_amount: "0x0", max_price_per_unit: "0x0" },
            l1_gas: { max_amount: "0x30000", max_price_per_unit: "0x300000000000" },
          },
        };
      }
      const { class_hash, transaction_hash } = await deployer.declareIfNot(payload, details);
      if (wait && transaction_hash) {
        await this.waitForTransaction(transaction_hash);
        console.log(`\t${contractName} declared`);
      }
      this.classCache[contractName] = class_hash;
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

function populatePayloadWithClassHashes(payload: DeclareContractPayload, contractName: string) {
  // TODO If we can have a mapping like this, we can save quite some time
  // TODO This is taking 10s to resolve
  // Lots of hashes tbd.
  // On my machine approx 7s for compiledClassHash and 3s for classHash
  // Only annoying when working on contracts... 
  // Should we remove the account && multisig maybe?
  // I have no clue why classHash is different from compiledClassHash
  if (contractName === "MockDapp") {
    payload.compiledClassHash = "0x4003961703135586f0b819506a9ac3beae88a7d76122bb8f27f4aeb9f446fa3";
    payload.classHash = "0x5bedb8d78b3874d1154d55adb41f08e4f576a48c8ead801b1d7c87ce59ce889";
  } else if (contractName === "ArgentAccount") {
    payload.compiledClassHash = "0x3e701e026a27215090f6d1c14d197622344c91f7305a31049e6635c7041bd20";
    payload.classHash = "0xbe187ea57c1dcf8b0b954bf68b7aeeafe071418acbfcab5951125dca69bb97";
  } else if (contractName === "Proxy") {
    payload.classHash = "0x660f41e2ffebe07703729569eac75f2a68000488b24df74e65acf59fe225b1e";
  } else if (contractName === "Account-0.2.3.1") {
    payload.classHash = "0x33434ad846cdd5f23eb73ff09fe6fddd568284a0fb7d1be20ee482f044dabe2";
  } else if (contractName === "ArgentMultisigAccount") {
    payload.compiledClassHash = "0x497cb1b672e790f05f001f1d4e0a927426b7fd93ee02679de416a28a5e5e0d";
    payload.classHash = "0x5e7606f1ef9471592b1071c0a3596efae6bf506fd0f6e4f96ad2adf4f8f65b";
  } else if (contractName == "MockFutureArgentAccount") {
    payload.compiledClassHash = "0x5bbf0b5cd500547b3db742c7039d808727fe56b0c63ecb6db9568ca83ffa421";
    payload.classHash = "0x4c02b9efb5c605e2086e14f5737112b101ca7c6d6c65532d528f42b02b858b2";
  } else if (contractName == "MockFutureArgentMultisig") {
    payload.compiledClassHash = "0x62a48ea2779a75a2fc6320acdcf985ce495dba356fa7cb2469054e0d497527b";
    payload.classHash = "0x249a0cc054900ad3ff97f42cc238b09afce38b3245df3a94f4c6adf5d4f3aa3";
  } else if (contractName.startsWith("/account-0.3.0-")) {
    payload.compiledClassHash = "0x29787a427a423ffc5986d43e630077a176e4391fcef3ebf36014b154069ae4";
    payload.classHash = "0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003";
  } else if (contractName.startsWith("/account-0.3.1-")) {
    payload.compiledClassHash = "0x1ec590df0895ac187b176f08fc1e77eb79bc0ac09427f871180a1b0d7df2266";
    payload.classHash = "0x29927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b";
  } else if (contractName.startsWith("/account-0.4.0-")) {
    payload.compiledClassHash = "0x7a663375245780bd307f56fde688e33e5c260ab02b76741a57711c5b60d47f6";
    payload.classHash = "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f";
  } else if (contractName.startsWith("/multisig-0.1.0-")) {
    payload.compiledClassHash = "0x121bd2f69b197378c63538f790b91875e56063aafebe4de4428003981ae64a4";
    payload.classHash = "0x737ee2f87ce571a58c6c8da558ec18a07ceb64a6172d5ec46171fbc80077a48";
  } else if (contractName.startsWith("/multisig-0.1.1-")) {
    payload.compiledClassHash = "0x326d68dc052576efaaa2d07138b9b3431d62882e8e05e87e1e2d30ebd9bca68";
    payload.classHash = "0x6e150953b26271a740bf2b6e9bca17cc52c68d765f761295de51ceb8526ee72";
  } else if (contractName.startsWith("/multisig-0.2.0-")) {
    payload.compiledClassHash = "0x22307f85476c6958917bcc395333384620e7f095aae2551871a13ff1ddbca3e";
    payload.classHash = "0x07aeca3456816e3b833506d7cc5c1313d371fbdb0ae95ee70af72a4ddbf42594";
  }
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
