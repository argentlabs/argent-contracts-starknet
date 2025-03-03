import * as env from "$env/static/public";
import {
  CallData,
  Contract,
  ProviderInterface,
  RPC,
  RpcProvider,
  Signer,
  SignerInterface,
  ec,
  encode,
  hash,
  transaction,
  typedData,
  uint256,
  type Abi,
  type Call,
  type RawArgs,
  type Signature,
  type V3DeclareSignerDetails,
  type V3DeployAccountSignerDetails,
  type V3InvocationsSignerDetails,
} from "starknet";
import { ArgentAccount } from "./account";

export type ProviderType = RpcProvider;

let deployer: ArgentAccount;

export const strkAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
let strkContract: Contract;

export async function getStrkContract(provider: ProviderType) {
  if (strkContract) {
    return strkContract;
  }
  strkContract = await loadContract(strkAddress, provider);
  return strkContract;
}

export async function loadDeployer(provider: ProviderType) {
  if (deployer) {
    return deployer;
  }
  if (providerUrl(provider).includes("localhost")) {
    const [{ address, private_key }] = await predeployedAccounts(provider);
    return new ArgentAccount(provider, address, private_key, "1", RPC.ETransactionVersion.V3);
  }
  if (!env.PUBLIC_DEPLOYER_ADDRESS || !env.PUBLIC_DEPLOYER_PRIVATE_KEY) {
    throw new Error("Need deployer credentials for non-devnet");
  }
  return new ArgentAccount(
    provider,
    env.PUBLIC_DEPLOYER_ADDRESS,
    env.PUBLIC_DEPLOYER_PRIVATE_KEY,
    undefined,
    RPC.ETransactionVersion.V3,
  );
}

export async function loadContract(contractAddress: string, provider: ProviderInterface) {
  const { abi } = await provider.getClassAt(contractAddress);
  if (!abi) {
    throw new Error("Error while getting ABI");
  }
  return new Contract(abi, contractAddress, provider);
}

export async function fundAccount(recipient: string, amount: number | bigint, provider: ProviderType) {
  console.log("funding account...");
  if (providerUrl(provider).includes("localhost")) {
    await mintStrk(recipient, provider);
    return;
  }
  const strkContract = await getStrkContract(provider);
  const deployer = await loadDeployer(provider);
  strkContract.connect(deployer);

  console.log("sending ETH from deployer to new account");
  const bn = uint256.bnToUint256(amount);
  const { transaction_hash } = await strkContract.invoke("transfer", CallData.compile([recipient, bn]));
  console.log("waiting for funding tx", transaction_hash);
  await provider.waitForTransaction(transaction_hash);
}

export class KeyPair extends Signer {
  constructor(pk?: string | bigint) {
    super(pk ? `${pk}` : `0x${encode.buf2hex(ec.starkCurve.utils.randomPrivateKey())}`);
  }

  public get privateKey() {
    return BigInt(this.pk as string);
  }

  public get publicKey() {
    return BigInt(ec.starkCurve.getStarkKey(this.pk));
  }

  public signHash(messageHash: string) {
    const { r, s } = ec.starkCurve.sign(messageHash, this.pk);
    return [r.toString(), s.toString()];
  }
}

export const randomKeyPair = () => new KeyPair();

/**
 * This class allows to easily implement custom signers by overriding the `signRaw` method.
 * This is based on Starknet.js implementation of Signer, but it delegates the actual signing to an abstract function
 */
export abstract class RawSigner implements SignerInterface {
  abstract signRaw(messageHash: string, isEstimation: boolean): Promise<Signature>;

  public async getPubKey(): Promise<string> {
    throw Error("This signer allows multiple public keys");
  }

  public async signMessage(typedDataArgument: typedData.TypedData, accountAddress: string): Promise<Signature> {
    const messageHash = typedData.getMessageHash(typedDataArgument, accountAddress);
    return this.signRaw(messageHash, false);
  }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: V3InvocationsSignerDetails,
    abis?: Abi[],
  ): Promise<Signature> {
    if (abis && abis.length !== transactions.length) {
      throw new Error("ABI must be provided for each transaction or no transaction");
    }
    // now use abi to display decoded data somewhere, but as this signer is headless, we can't do that
    const calldata = transaction.getExecuteCalldata(transactions, transactionsDetail.cairoVersion);
    const messageHash = hash.calculateInvokeTransactionHash({
      senderAddress: transactionsDetail.walletAddress,
      compiledCalldata: calldata,
      ...transactionsDetail,
    });

    const isEstimation = BigInt(transactionsDetail.maxFee) === 0n;
    return this.signRaw(messageHash, isEstimation);
  }

  public async signDeployAccountTransaction({
    classHash,
    contractAddress,
    constructorCalldata,
    addressSalt,
    maxFee,
    version,
    chainId,
    nonce,
  }: V3DeployAccountSignerDetails) {
    const messageHash = hash.calculateDeployAccountTransactionHash({
      contractAddress,
      classHash,
      constructorCalldata: CallData.compile(constructorCalldata),
      salt: BigInt(addressSalt),
      version: version,
      maxFee,
      chainId,
      nonce,
    });

    const isEstimation = BigInt(maxFee) === 0n;
    return this.signRaw(messageHash, isEstimation);
  }

  public async signDeclareTransaction(
    // contractClass: ContractClass,  // Should be used once class hash is present in ContractClass
    { classHash, maxFee, senderAddress, chainId, version, nonce, compiledClassHash }: V3DeclareSignerDetails,
  ) {
    const messageHash = hash.calculateDeclareTransactionHash({
      classHash,
      senderAddress,
      version,
      maxFee,
      chainId,
      nonce,
      compiledClassHash,
    });

    const isEstimation = BigInt(maxFee) === 0n;
    return this.signRaw(messageHash, isEstimation);
  }
}

export const normalizeTransactionHash = (transactionHash: string) =>
  transactionHash.replace(/^0x/, "").padStart(64, "0");

export async function predeployedAccounts(
  provider: ProviderType,
): Promise<Array<{ address: string; private_key: string }>> {
  return handleGet(provider, "predeployed_accounts");
}

export async function feeToken(provider: ProviderType): Promise<{ symbol: string; address: string }> {
  return handleGet(provider, "fee_token");
}

export async function mintStrk(address: string, provider: ProviderType) {
  await handlePost(provider, "mint", { address, amount: 100e18, unit: "FRI" });
}

async function handleGet(provider: any, path: string, args?: string) {
  const origin = providerUrl(provider);
  const response = await fetch(`${origin}/${path}`, {
    method: "GET",
    headers: { "Content-Type": "application/json" },
  });
  return response.json();
}

async function handlePost(provider: ProviderInterface, path: string, payload?: RawArgs) {
  const origin = providerUrl(provider);
  const response = await fetch(`${origin}/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new Error(`HTTP error! Status: ${response.status} Message: ${await response.text()}`);
  }
}

function providerUrl(provider: ProviderInterface): string {
  return provider.channel.nodeUrl;
}
