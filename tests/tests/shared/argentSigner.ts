import {
  Abi,
  Call,
  CallData,
  DeclareSignerDetails,
  DeployAccountSignerDetails,
  InvocationsSignerDetails,
  Signature,
  SignerInterface,
  ec,
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

class ArgentSigner extends RawSigner {
  constructor(protected ownerPrivateKey: string, protected guardianPrivateKey?: string) {
    super();
  }
  public getOwnerKey(): string {
    return ec.starkCurve.getStarkKey(this.ownerPrivateKey);
  }

  public getGuardianKey(): string | null {
    if (this.guardianPrivateKey) {
      return ec.starkCurve.getStarkKey(this.guardianPrivateKey);
    } else {
      return null;
    }
  }

  public async signRaw(msgHash: string): Promise<Signature> {
    if (this.guardianPrivateKey) {
      return new ConcatSigner([this.ownerPrivateKey, this.guardianPrivateKey]).signRaw(msgHash);
    } else {
      return ec.starkCurve.sign(msgHash, this.ownerPrivateKey);
    }
  }
}

class ConcatSigner extends RawSigner {
  constructor(protected privateKeys: string[]) {
    super();
  }

  async signRaw(msgHash: string): Promise<Signature> {
    return (
      await Promise.all(
        this.privateKeys.map(async (pk) => {
          const signature = ec.starkCurve.sign(msgHash, pk);
          return [signature.r.toString(), signature.s.toString()];
        }),
      )
    ).flat();
  }
}

export { ArgentSigner, ConcatSigner };
