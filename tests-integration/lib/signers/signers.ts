import {
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  Call,
  CallData,
  DeclareSignerDetails,
  DeployAccountSignerDetails,
  InvocationsSignerDetails,
  Signature,
  SignerInterface,
  ec,
  encode,
  hash,
  transaction,
  typedData,
  RPC,
  V2InvocationsSignerDetails,
  V3InvocationsSignerDetails,
  V2DeployAccountSignerDetails,
  V3DeployAccountSignerDetails,
  V2DeclareSignerDetails,
  V3DeclareSignerDetails,
  stark,
  Calldata,
  shortString,
} from "starknet";

/**
 * This class allows to easily implement custom signers by overriding the `signRaw` method.
 * This is based on Starknet.js implementation of Signer, but it delegates the actual signing to an abstract function
 */
export abstract class RawSigner implements SignerInterface {
  abstract signRaw(messageHash: string): Promise<string[]>;

  public async getPubKey(): Promise<string> {
    throw new Error("This signer allows multiple public keys");
  }

  public async signMessage(typedDataArgument: typedData.TypedData, accountAddress: string): Promise<Signature> {
    const messageHash = typedData.getMessageHash(typedDataArgument, accountAddress);
    return this.signRaw(messageHash);
  }

  public async signTransaction(transactions: Call[], details: InvocationsSignerDetails): Promise<Signature> {
    const compiledCalldata = transaction.getExecuteCalldata(transactions, details.cairoVersion);
    let msgHash;

    // TODO: How to do generic union discriminator for all like this
    if (Object.values(RPC.ETransactionVersion2).includes(details.version as any)) {
      const det = details as V2InvocationsSignerDetails;
      msgHash = hash.calculateInvokeTransactionHash({
        ...det,
        senderAddress: det.walletAddress,
        compiledCalldata,
        version: det.version,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(details.version as any)) {
      const det = details as V3InvocationsSignerDetails;
      msgHash = hash.calculateInvokeTransactionHash({
        ...det,
        senderAddress: det.walletAddress,
        compiledCalldata,
        version: det.version,
        nonceDataAvailabilityMode: stark.intDAM(det.nonceDataAvailabilityMode),
        feeDataAvailabilityMode: stark.intDAM(det.feeDataAvailabilityMode),
      });
    } else {
      throw new Error("unsupported signTransaction version");
    }
    return await this.signRaw(msgHash);
  }

  public async signDeployAccountTransaction(details: DeployAccountSignerDetails): Promise<Signature> {
    const compiledConstructorCalldata = CallData.compile(details.constructorCalldata);
    /*     const version = BigInt(details.version).toString(); */
    let msgHash;

    if (Object.values(RPC.ETransactionVersion2).includes(details.version as any)) {
      const det = details as V2DeployAccountSignerDetails;
      msgHash = hash.calculateDeployAccountTransactionHash({
        ...det,
        salt: det.addressSalt,
        constructorCalldata: compiledConstructorCalldata,
        version: det.version,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(details.version as any)) {
      const det = details as V3DeployAccountSignerDetails;
      msgHash = hash.calculateDeployAccountTransactionHash({
        ...det,
        salt: det.addressSalt,
        compiledConstructorCalldata,
        version: det.version,
        nonceDataAvailabilityMode: stark.intDAM(det.nonceDataAvailabilityMode),
        feeDataAvailabilityMode: stark.intDAM(det.feeDataAvailabilityMode),
      });
    } else {
      throw new Error(`unsupported signDeployAccountTransaction version: ${details.version}}`);
    }

    return await this.signRaw(msgHash);
  }

  public async signDeclareTransaction(
    // contractClass: ContractClass,  // Should be used once class hash is present in ContractClass
    details: DeclareSignerDetails,
  ): Promise<Signature> {
    let msgHash;

    if (Object.values(RPC.ETransactionVersion2).includes(details.version as any)) {
      const det = details as V2DeclareSignerDetails;
      msgHash = hash.calculateDeclareTransactionHash({
        ...det,
        version: det.version,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(details.version as any)) {
      const det = details as V3DeclareSignerDetails;
      msgHash = hash.calculateDeclareTransactionHash({
        ...det,
        version: det.version,
        nonceDataAvailabilityMode: stark.intDAM(det.nonceDataAvailabilityMode),
        feeDataAvailabilityMode: stark.intDAM(det.feeDataAvailabilityMode),
      });
    } else {
      throw new Error("unsupported signDeclareTransaction version");
    }

    return await this.signRaw(msgHash);
  }
}

export class MultisigSigner extends RawSigner {
  constructor(public keys: KeyPair[]) {
    super();
  }

  async signRaw(messageHash: string): Promise<string[]> {
    const keys = [];
    for (const key of this.keys) {
      keys.push(await key.signRaw(messageHash));
    }
    return [keys.length.toString(), keys.flat()].flat();
  }
}

export class ArgentSigner extends MultisigSigner {
  constructor(
    public owner: KeyPair = randomStarknetKeyPair(),
    public guardian?: KeyPair,
  ) {
    const signers = [owner];
    if (guardian) {
      signers.push(guardian);
    }
    super(signers);
  }
}

export abstract class KeyPair extends RawSigner {
  abstract get signer(): CairoCustomEnum;
  abstract get guid(): bigint;
  abstract get storedValue(): bigint;

  public get compiledSigner(): Calldata {
    return CallData.compile([this.signer]);
  }

  public get signerAsOption() {
    return new CairoOption(CairoOptionVariant.Some, {
      signer: this.signer,
    });
  }
  public get compiledSignerAsOption() {
    return CallData.compile([this.signerAsOption]);
  }
}

export class StarknetKeyPair extends KeyPair {
  pk: string;

  constructor(pk?: string | bigint) {
    super();
    this.pk = pk ? `${pk}` : `0x${encode.buf2hex(ec.starkCurve.utils.randomPrivateKey())}`;
  }

  public get privateKey(): string {
    return this.pk;
  }

  public get publicKey() {
    return BigInt(ec.starkCurve.getStarkKey(this.pk));
  }

  public get guid() {
    return BigInt(hash.computePoseidonHash(shortString.encodeShortString("Starknet Signer"), this.publicKey));
  }

  public get storedValue() {
    return this.publicKey;
  }

  public get signer(): CairoCustomEnum {
    return signerTypeToCustomEnum(SignerType.Starknet, { signer: this.publicKey });
  }

  public async signRaw(messageHash: string): Promise<string[]> {
    const { r, s } = ec.starkCurve.sign(messageHash, this.pk);
    return starknetSignatureType(this.publicKey, r, s);
  }
}

export class EstimateStarknetKeyPair extends KeyPair {
  readonly pubKey: bigint;

  constructor(pubKey: bigint) {
    super();
    this.pubKey = pubKey;
  }

  public get privateKey(): string {
    throw new Error("EstimateStarknetKeyPair does not have a private key");
  }

  public get publicKey() {
    return this.pubKey;
  }

  public get guid() {
    return this.publicKey;
  }

  public get signer(): CairoCustomEnum {
    return signerTypeToCustomEnum(SignerType.Starknet, { signer: this.publicKey });
  }

  public async signRaw(messageHash: string): Promise<string[]> {
    const fakeR = "0x6cefb49a1f4eb406e8112db9b8cdf247965852ddc5ca4d74b09e42471689495";
    const fakeS = "0x25760910405a052b7f08ec533939c54948bc530c662c5d79e8ff416579087f7";
    return starknetSignatureType(this.publicKey, fakeR, fakeS);
  }
}

export function starknetSignatureType(
  signer: bigint | number | string,
  r: bigint | number | string,
  s: bigint | number | string,
) {
  return CallData.compile([signerTypeToCustomEnum(SignerType.Starknet, { signer, r, s })]);
}

export function zeroStarknetSignatureType() {
  return signerTypeToCustomEnum(SignerType.Starknet, { signer: 0 });
}

// reflects the signer type in signer_signature.cairo
// needs to be updated for the signer types
// used to convert signertype to guid
export enum SignerType {
  Starknet,
  Secp256k1,
  Secp256r1,
  Eip191,
  Webauthn,
}

export function signerTypeToCustomEnum(my_enum: SignerType, value: any): CairoCustomEnum {
  let Starknet;
  let Secp256k1;
  let Secp256r1;
  let Eip191;
  let Webauthn;
  switch (my_enum) {
    case SignerType.Starknet:
      Starknet = value;
      break;
    case SignerType.Secp256k1:
      Secp256k1 = value;
      break;
    case SignerType.Secp256r1:
      Secp256r1 = value;
      break;
    case SignerType.Eip191:
      Eip191 = value;
      break;
    case SignerType.Webauthn:
      Webauthn = value;
      break;
    default:
      throw new Error(`Unknown SignerType`);
  }

  return new CairoCustomEnum({
    Starknet,
    Secp256k1,
    Secp256r1,
    Eip191,
    Webauthn,
  });
}

export function sortByGuid(keys: KeyPair[]) {
  return keys.sort((n1, n2) => (n1.guid < n2.guid ? -1 : 1));
}

export const randomStarknetKeyPair = () => new StarknetKeyPair();
export const randomStarknetKeyPairs = (length: number) => Array.from({ length }, randomStarknetKeyPair);
