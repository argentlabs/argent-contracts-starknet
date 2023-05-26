import {
  Abi,
  ArraySignatureType,
  Call,
  CallData,
  DeclareSignerDetails,
  DeployAccountSignerDetails,
  InvocationsSignerDetails,
  Signature,
  SignerInterface,
  WeierstrassSignatureType,
  ec,
  encode,
  hash,
  transaction,
  typedData,
} from "starknet";

/**
 * This class allows to easily implement custom signers by overriding the `signRaw` method.
 * This is based on Starknet.js implementation of Signer, but it delegates the actual signing to an abstract function
 */
abstract class RawSigner implements SignerInterface {
  abstract signRaw(messageHash: string): Promise<Signature>;

  public async getPubKey(): Promise<string> {
    throw Error("This signer allows multiple public keys");
  }

  public async signMessage(typedDataArgument: typedData.TypedData, accountAddress: string): Promise<Signature> {
    const msgHash = typedData.getMessageHash(typedDataArgument, accountAddress);
    return this.signRaw(msgHash);
  }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: InvocationsSignerDetails,
    abis?: Abi[],
  ): Promise<Signature> {
    if (abis && abis.length !== transactions.length) {
      throw new Error("ABI must be provided for each transaction or no transaction");
    }
    // now use abi to display decoded data somewhere, but as this signer is headless, we can't do that
    const calldata = transaction.getExecuteCalldata(transactions, transactionsDetail.cairoVersion);

    const msgHash = hash.calculateTransactionHash(
      transactionsDetail.walletAddress,
      transactionsDetail.version,
      calldata,
      transactionsDetail.maxFee,
      transactionsDetail.chainId,
      transactionsDetail.nonce,
    );
    return this.signRaw(msgHash);
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
  }: DeployAccountSignerDetails) {
    const msgHash = hash.calculateDeployAccountTransactionHash(
      contractAddress,
      classHash,
      CallData.compile(constructorCalldata),
      addressSalt,
      version,
      maxFee,
      chainId,
      nonce,
    );

    return this.signRaw(msgHash);
  }

  public async signDeclareTransaction(
    // contractClass: ContractClass,  // Should be used once class hash is present in ContractClass
    { classHash, senderAddress, chainId, maxFee, version, nonce, compiledClassHash }: DeclareSignerDetails,
  ) {
    const msgHash = hash.calculateDeclareTransactionHash(
      classHash,
      senderAddress,
      version,
      maxFee,
      chainId,
      nonce,
      compiledClassHash,
    );

    return this.signRaw(msgHash);
  }
}

export class ArgentSigner extends RawSigner {
  constructor(public ownerPrivateKey: string = randomKeyPair().privateKey, public guardianPrivateKey?: string) {
    super();
  }

  public getOwnerKey(): string {
    return ec.starkCurve.getStarkKey(this.ownerPrivateKey);
  }

  public getGuardianKey(): string | null {
    if (this.guardianPrivateKey) {
      return ec.starkCurve.getStarkKey(this.guardianPrivateKey);
    }
    return null;
  }

  public async signRaw(msgHash: string): Promise<ArraySignatureType> {
    if (this.guardianPrivateKey) {
      return new ConcatSigner([this.ownerPrivateKey, this.guardianPrivateKey]).signRaw(msgHash);
    }
    const ownerSignature = ec.starkCurve.sign(msgHash, this.ownerPrivateKey) as WeierstrassSignatureType;
    return [ownerSignature.r.toString(), ownerSignature.s.toString()];
  }
}

export class ConcatSigner extends RawSigner {
  constructor(public privateKeys: string[]) {
    super();
  }

  async signRaw(msgHash: string): Promise<ArraySignatureType> {
    return this.privateKeys
      .map((privateKey) => {
        const signature = ec.starkCurve.sign(msgHash, privateKey);
        return [signature.r.toString(), signature.s.toString()];
      })
      .flat();
  }
}

export class MultisigSigner extends RawSigner {
  constructor(public keys: KeyPair[]) {
    super();
  }

  async signRaw(msgHash: string): Promise<ArraySignatureType> {
    const signerSignatures = this.keys.map(({ privateKey, publicKey: signer }) => {
      const { r, s } = ec.starkCurve.sign(msgHash, privateKey);
      return { signer, signature_r: r.toString(), signature_s: s.toString() };
    });
    return CallData.compile(signerSignatures);
  }
}

export interface KeyPair {
  readonly publicKey: string;
  readonly privateKey: string;
}

export const randomKeyPair = () => {
  const privateKey = "0x" + encode.buf2hex(ec.starkCurve.utils.randomPrivateKey());
  const publicKey = ec.starkCurve.getStarkKey(privateKey);
  return { publicKey, privateKey };
};

export const randomKeyPairs = (length: number) => Array.from({ length }, randomKeyPair);
