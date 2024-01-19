import {
  Abi,
  ArraySignatureType,
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  Call,
  CallData,
  DeclareSignerDetails,
  DeployAccountSignerDetails,
  InvocationsSignerDetails,
  Signature,
  Signer,
  SignerInterface,
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
export abstract class RawSigner implements SignerInterface {
  abstract signRaw(messageHash: string): Promise<Signature>;

  public async getPubKey(): Promise<string> {
    throw Error("This signer allows multiple public keys");
  }

  public async signMessage(typedDataArgument: typedData.TypedData, accountAddress: string): Promise<Signature> {
    const messageHash = typedData.getMessageHash(typedDataArgument, accountAddress);
    return this.signRaw(messageHash);
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

    const messageHash = hash.calculateTransactionHash(
      transactionsDetail.walletAddress,
      transactionsDetail.version,
      calldata,
      transactionsDetail.maxFee,
      transactionsDetail.chainId,
      transactionsDetail.nonce,
    );
    return this.signRaw(messageHash);
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
    const messageHash = hash.calculateDeployAccountTransactionHash(
      contractAddress,
      classHash,
      CallData.compile(constructorCalldata),
      addressSalt,
      version,
      maxFee,
      chainId,
      nonce,
    );

    return this.signRaw(messageHash);
  }

  public async signDeclareTransaction(
    // contractClass: ContractClass,  // Should be used once class hash is present in ContractClass
    { classHash, senderAddress, chainId, maxFee, version, nonce, compiledClassHash }: DeclareSignerDetails,
  ) {
    const messageHash = hash.calculateDeclareTransactionHash(
      classHash,
      senderAddress,
      version,
      maxFee,
      chainId,
      nonce,
      compiledClassHash,
    );

    return this.signRaw(messageHash);
  }
}

export class MultisigSigner extends RawSigner {
  constructor(public keys: KeyPair[]) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const keys = this.keys.map((key) => key.signHash(messageHash));
    return [keys.length.toString(), keys.flat()].flat();
  }
}

export class ArgentSigner extends MultisigSigner {
  constructor(
    public owner: KeyPair = randomKeyPair(),
    public guardian?: KeyPair,
  ) {
    const signers = [owner];
    if (guardian) {
      signers.push(guardian);
    }
    super(signers);
  }
}

export class LegacyArgentSigner extends RawSigner {
  constructor(
    public owner: LegacyKeyPair = new LegacyKeyPair(),
    public guardian?: LegacyKeyPair,
  ) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const signature = this.owner.signHash(messageHash);
    if (this.guardian) {
      const [guardianR, guardianS] = this.guardian.signHash(messageHash);
      signature[2] = guardianR;
      signature[3] = guardianS;
    }
    return signature;
  }
}

export class LegacyMultisigSigner extends RawSigner {
  constructor(public keys: KeyPair[]) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const keys = this.keys.map((key) => key.signHash(messageHash));
    return keys.flat();
  }
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
    return starknetSignatureType(this.publicKey, r, s);
  }
}

export class LegacyKeyPair extends KeyPair {
  public signHash(messageHash: string) {
    const { r, s } = ec.starkCurve.sign(messageHash, this.pk);
    return [r.toString(), s.toString()];
  }
}

export function starknetSignatureType(
  signer: bigint | number | string,
  r: bigint | number | string,
  s: bigint | number | string,
) {
  return CallData.compile([
    new CairoCustomEnum({
      Starknet: { signer, r, s },
      Secp256k1: undefined,
      Secp256r1: undefined,
      Webauthn: undefined,
    }),
  ]);
}

export function compiledStarknetSigner(signer: bigint | number | string) {
  return CallData.compile([starknetSigner(signer)]);
}
export function starknetSigner(signer: bigint | number | string) {
  return new CairoCustomEnum({
    Starknet: { signer },
    Secp256k1: undefined,
    Secp256r1: undefined,
    Webauthn: undefined,
  });
}

export function compiledSignerOption(signer: bigint | undefined) {
  return CallData.compile([signerOption(signer)]);
}

export function signerOption(signer: bigint | undefined) {
  if (signer) {
    return new CairoOption<any>(CairoOptionVariant.Some, { signer: starknetSigner(signer) });
  }
  return new CairoOption<any>(CairoOptionVariant.None);
}

export const randomKeyPair = () => new KeyPair();

export const randomKeyPairs = (length: number) => Array.from({ length }, randomKeyPair);
