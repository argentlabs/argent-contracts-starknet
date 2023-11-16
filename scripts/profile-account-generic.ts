import { Account, ArraySignatureType, CairoCustomEnum, CallData, InvokeFunctionResponse, hash, num } from "starknet";
import {
  EthKeyPair,
  KeyPair,
  RawSigner,
  declareContract,
  deployer,
  fundAccount,
  loadContract,
  provider,
  randomKeyPair,
} from "../tests-integration/lib";
import { profileGasUsage } from "../tests-integration/lib/gas";

const genericAccountClassHash = await declareContract("ArgentGenericAccount");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);

const ethUsd = 1800n;

const table: Record<string, any> = {};

async function reportProfile(name: string, response: InvokeFunctionResponse) {
  const report = await profileGasUsage(response);
  const { actualFee, gasUsed, computationGas, l1CalldataGas, executionResources } = report;
  console.dir(report, { depth: null });
  const feeUsd = Number(actualFee * ethUsd) / Number(10n ** 18n);
  table[name] = {
    actualFee: Number(actualFee),
    feeUsd: Number(feeUsd.toFixed(2)),
    gasUsed: Number(gasUsed),
    computationGas: Number(computationGas),
    l1CalldataGas: Number(l1CalldataGas),
    ...executionResources,
  };
}

class GenericSigner extends RawSigner {
  constructor(
    public key: KeyPair,
    public signature_type: CairoCustomEnum,
  ) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    return CallData.compile({
      signer: this.key.publicKey,
      signer_type: this.signature_type,
      signature: this.key.signHash(messageHash),
    });
  }
}
const StarknetSignatureType = new CairoCustomEnum({
  Starknet: {},
  Secp256k1: undefined,
  Webauthn: undefined,
  Secp256r1: undefined,
});

const EthereumSignatureType = new CairoCustomEnum({
  Starknet: undefined,
  Secp256k1: {},
  Webauthn: undefined,
  Secp256r1: undefined,
});

{
  const name = "Generic account - Starknet signature";
  console.log(name);
  const owner = randomKeyPair();
  const account = await deployGenericAccount(genericAccountClassHash, owner, StarknetSignatureType);
  testDappContract.connect(account);
  await reportProfile(name, await testDappContract.set_number(42));
}

{
  const name = "Generic account - Ethereum signature";
  console.log(name);
  const owner = new EthKeyPair();
  const account = await deployGenericAccount(genericAccountClassHash, owner, EthereumSignatureType);
  testDappContract.connect(account);
  await reportProfile(name, await testDappContract.set_number(42));
}

async function deployGenericAccount(accountClassHash: string, owner: KeyPair, signatureType: CairoCustomEnum) {
  const salt = num.toHex(randomKeyPair().privateKey);
  const constructorCalldata = CallData.compile({ new_threshold: 1, signers: [num.toHex(owner.publicKey)] });

  const contractAddress = hash.calculateContractAddressFromHash(salt, accountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15); // 0.001 ETH
  const account = new Account(provider, contractAddress, owner, "1");

  account.signer = new GenericSigner(owner, signatureType);

  const { transaction_hash } = await account.deploySelf({
    classHash: accountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  return account;
}

console.table(table);
