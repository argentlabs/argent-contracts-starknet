import {
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  type Call,
  CallData,
  type Calldata,
  type DeclareSignerDetails,
  type DeployAccountSignerDetails,
  ETransactionVersion,
  type InvocationsSignerDetails,
  type Signature,
  SignerInterface,
  type TypedData,
  hash,
  stark,
  transaction,
  typedData,
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

  public async signMessage(typedDataArgument: TypedData, accountAddress: string): Promise<Signature> {
    const messageHash = typedData.getMessageHash(typedDataArgument, accountAddress);
    return this.signRaw(messageHash);
  }

  public async signTransaction(transactions: Call[], details: InvocationsSignerDetails): Promise<Signature> {
    if (details.version !== ETransactionVersion.V3 && details.version !== ETransactionVersion.F3) {
      throw new Error("unsupported signTransaction version");
    }

    const compiledCalldata = transaction.getExecuteCalldata(transactions, details.cairoVersion);
    const msgHash = hash.calculateInvokeTransactionHash({
      ...details,
      senderAddress: details.walletAddress,
      compiledCalldata,
      nonceDataAvailabilityMode: stark.intDAM(details.nonceDataAvailabilityMode),
      feeDataAvailabilityMode: stark.intDAM(details.feeDataAvailabilityMode),
    });
    return await this.signRaw(msgHash);
  }

  public async signDeployAccountTransaction(details: DeployAccountSignerDetails): Promise<Signature> {
    if (details.version !== ETransactionVersion.V3 && details.version !== ETransactionVersion.F3) {
      throw new Error("unsupported signDeployAccountTransaction version");
    }
    const compiledConstructorCalldata = CallData.compile(details.constructorCalldata);

    const msgHash = hash.calculateDeployAccountTransactionHash({
      ...details,
      salt: details.addressSalt,
      compiledConstructorCalldata,
      nonceDataAvailabilityMode: stark.intDAM(details.nonceDataAvailabilityMode),
      feeDataAvailabilityMode: stark.intDAM(details.feeDataAvailabilityMode),
    });

    return await this.signRaw(msgHash);
  }

  public async signDeclareTransaction(
    // contractClass: ContractClass,  // Should be used once class hash is present in ContractClass
    details: DeclareSignerDetails,
  ): Promise<Signature> {
    if (details.version !== ETransactionVersion.V3 && details.version !== ETransactionVersion.F3) {
      throw new Error("unsupported signDeclareTransaction version");
    }
    const msgHash = hash.calculateDeclareTransactionHash({
      ...details,
      nonceDataAvailabilityMode: stark.intDAM(details.nonceDataAvailabilityMode),
      feeDataAvailabilityMode: stark.intDAM(details.feeDataAvailabilityMode),
    });

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
    public owner: KeyPair,
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
  abstract get estimateSigner(): KeyPair;
  abstract get signerType(): SignerType;

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

export abstract class EstimateKeyPair extends KeyPair {
  public get estimateSigner(): KeyPair {
    return this;
  }
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

export function signerTypeToCustomEnum(signerType: SignerType, value: any): CairoCustomEnum {
  const contents = {
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: undefined,
    Eip191: undefined,
    Webauthn: undefined,
  };

  if (signerType === SignerType.Starknet) {
    contents.Starknet = value;
  } else if (signerType === SignerType.Secp256k1) {
    contents.Secp256k1 = value;
  } else if (signerType === SignerType.Secp256r1) {
    contents.Secp256r1 = value;
  } else if (signerType === SignerType.Eip191) {
    contents.Eip191 = value;
  } else if (signerType === SignerType.Webauthn) {
    contents.Webauthn = value;
  } else {
    throw new Error(`Unknown SignerType`);
  }

  return new CairoCustomEnum(contents);
}
