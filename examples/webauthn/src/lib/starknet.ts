import * as env from "$env/static/public";
import {
  CallData,
  Contract,
  hash,
  Signer,
  encode,
  ec,
  type RawArgs,
  SignerInterface,
  type Signature,
  typedData,
  transaction,
  type Abi,
  type Call,
  ProviderInterface,
  RpcProvider,
  Account,
  uint256,
  type V2InvocationsSignerDetails,
  type V2DeployAccountSignerDetails,
  type V2DeclareSignerDetails,
  RPC,
} from "starknet";

export type ProviderType = RpcProvider;

let deployer: Account;

export const ethAddress = "0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7";
let ethContract: Contract;

export async function getEthContract(provider: ProviderType) {
  if (ethContract) {
    return ethContract;
  }
  ethContract = await loadContract(ethAddress, provider);
  return ethContract;
}

export async function loadDeployer(provider: ProviderType) {
  if (deployer) {
    return deployer;
  }
  if (providerUrl(provider).includes("localhost")) {
    const [{ address, private_key }] = await predeployedAccounts(provider);
    return new Account(provider, address, private_key);
  }
  if (!env.PUBLIC_DEPLOYER_ADDRESS || !env.PUBLIC_DEPLOYER_PRIVATE_KEY) {
    throw new Error("Need deployer credentials for non-devnet");
  }
  return new Account(
    provider,
    env.PUBLIC_DEPLOYER_ADDRESS,
    env.PUBLIC_DEPLOYER_PRIVATE_KEY,
    undefined,
    RPC.ETransactionVersion.V2,
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
    await mintEth(recipient, provider);
    return;
  }
  const ethContract = await getEthContract(provider);
  const deployer = await loadDeployer(provider);
  ethContract.connect(deployer);

  console.log("sending ETH from deployer to new account");
  const bn = uint256.bnToUint256(amount);
  const { transaction_hash } = await ethContract.invoke("transfer", CallData.compile([recipient, bn]));
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
    transactionsDetail: V2InvocationsSignerDetails,
    abis?: Abi[],
  ): Promise<Signature> {
    if (abis && abis.length !== transactions.length) {
      throw new Error("ABI must be provided for each transaction or no transaction");
    }
    // now use abi to display decoded data somewhere, but as this signer is headless, we can't do that
    const calldata = transaction.getExecuteCalldata(transactions, transactionsDetail.cairoVersion);
    const messageHash = hash.calculateInvokeTransactionHash({
      senderAddress: transactionsDetail.walletAddress,
      version: transactionsDetail.version,
      compiledCalldata: calldata,
      maxFee: transactionsDetail.maxFee,
      chainId: transactionsDetail.chainId,
      nonce: transactionsDetail.nonce,
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
  }: V2DeployAccountSignerDetails) {
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
    { classHash, maxFee, senderAddress, chainId, version, nonce, compiledClassHash }: V2DeclareSignerDetails,
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

export async function mintEth(address: string, provider: ProviderType) {
  await handlePost(provider, "mint", { address, amount: 1e18, lite: true });
}

async function handleGet(provider: any, path: string, args?: string) {
  const origin = providerUrl(provider).replace("/rpc", "");
  const response = await fetch(`${origin}/${path}`, {
    method: "GET",
    headers: { "Content-Type": "application/json" },
  });
  return response.json();
}

async function handlePost(provider: ProviderInterface, path: string, payload?: RawArgs) {
  const origin = providerUrl(provider).replace("/rpc", "");
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
