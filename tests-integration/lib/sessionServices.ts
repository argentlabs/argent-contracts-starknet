import {
  typedData,
  ArraySignatureType,
  ec,
  CallData,
  Signature,
  InvocationsSignerDetails,
  Call,
  shortString,
  hash,
  transaction,
  selector,
  Account,
  uint256,
  merkle,
} from "starknet";
import {
  OffChainSession,
  KeyPair,
  randomKeyPair,
  AllowedMethod,
  TokenAmount,
  RawSigner,
  getSessionTypedData,
  ALLOWED_METHOD_HASH,
  StarknetSig,
} from ".";

const SESSION_MAGIC = shortString.encodeShortString("session-token");

export class ArgentX {
  constructor(
    public account: Account,
    public backendService: BackendService,
  ) {}

  public async getOffchainSignature(sessionRequest: OffChainSession): Promise<ArraySignatureType> {
    const sessionTypedData = await getSessionTypedData(sessionRequest);
    return (await this.account.signMessage(sessionTypedData)) as ArraySignatureType;
  }
}

export class BackendService {
  constructor(private guardian: KeyPair) {}

  public async signTxAndSession(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
    sessionTokenToSign: OffChainSession,
  ): Promise<StarknetSig> {
    // verify session param correct

    // extremely simplified version of the backend verification
    const allowed_methods = sessionTokenToSign.allowed_methods;
    if (
      !calls.every((call) => {
        return allowed_methods.some(
          (method) =>
            method["Contract Address"] === call.contractAddress &&
            method.selector === selector.getSelectorFromName(call.entrypoint),
        );
      })
    ) {
      throw new Error("Call not allowed");
    }

    const calldata = transaction.getExecuteCalldata(calls, transactionsDetail.cairoVersion);

    const txHash = hash.calculateTransactionHash(
      transactionsDetail.walletAddress,
      transactionsDetail.version,
      calldata,
      transactionsDetail.maxFee,
      transactionsDetail.chainId,
      transactionsDetail.nonce,
    );

    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(sessionTokenToSign),
      transactionsDetail.walletAddress,
    );
    const sessionWithTxHash = ec.starkCurve.pedersen(txHash, sessionMessageHash);
    const [r, s] = this.guardian.signHash(sessionWithTxHash);
    return { r: BigInt(r), s: BigInt(s) };
  }

  public getGuardianKey(): bigint {
    return this.guardian.publicKey;
  }
}

export class DappService {
  constructor(
    public argentBackend: BackendService,
    public sessionKey: KeyPair = randomKeyPair(),
  ) {}

  public createSessionRequest(
    allowed_methods: AllowedMethod[],
    token_amounts: TokenAmount[],
    expires_at = 150,
    max_fee_usage = { token_address: "0x0000", amount: uint256.bnToUint256(1000000n) },
    nft_contracts: string[] = [],
  ): OffChainSession {
    return {
      expires_at,
      allowed_methods,
      token_amounts,
      nft_contracts,
      max_fee_usage,
      guardian_key: this.argentBackend.getGuardianKey(),
      session_key: this.sessionKey.publicKey,
    };
  }

  public get keypair(): KeyPair {
    return this.sessionKey;
  }
}

export class DappSigner extends RawSigner {
  constructor(
    public argentBackend: BackendService,
    public sessionKeyPair: KeyPair,
    public accountSessionSignature: ArraySignatureType,
    public completedSession: OffChainSession,
  ) {
    super();
  }

  public async signRaw(messageHash: string): Promise<Signature> {
    throw new Error("Dapp cannot sign raw message");
  }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<ArraySignatureType> {
    const txHash = await this.getTransactionHash(transactions, transactionsDetail);
    const leaves = this.completedSession.allowed_methods.map((method) =>
      hash.computeHashOnElements([ALLOWED_METHOD_HASH, method["Contract Address"], method.selector]),
    );
    const session = {
      expires_at: this.completedSession.expires_at,
      allowed_methods_root: new merkle.MerkleTree(leaves).root.toString(),
      token_amounts: this.completedSession.token_amounts,
      nft_contracts: this.completedSession.nft_contracts,
      max_fee_usage: this.completedSession.max_fee_usage,
      guardian_key: this.completedSession.guardian_key,
      session_key: this.completedSession.session_key,
    };

    const sessionToken = {
      session,
      account_signature: this.accountSessionSignature,
      session_signature: await this.signTxAndSession(txHash, transactionsDetail),
      backend_signature: await this.argentBackend.signTxAndSession(
        transactions,
        transactionsDetail,
        this.completedSession,
      ),
      proofs: this.getSessionProofs(transactions, this.completedSession.allowed_methods, leaves),
    };

    return [SESSION_MAGIC, ...CallData.compile({ ...sessionToken })];
  }

  private async signTxAndSession(
    transactionHash: string,
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<StarknetSig> {
    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(this.completedSession),
      transactionsDetail.walletAddress,
    );
    const sessionWithTxHash = ec.starkCurve.pedersen(transactionHash, sessionMessageHash);
    const [r, s] = this.sessionKeyPair.signHash(sessionWithTxHash);
    return {
      r: BigInt(r),
      s: BigInt(s),
    };
  }

  private getSessionProofs(calls: Call[], allowedMethods: AllowedMethod[], leaves: string[]): string[][] {
    const tree = new merkle.MerkleTree(leaves);

    return calls.map((call) => {
      const allowedIndex = allowedMethods.findIndex((allowedMethod) => {
        return (
          allowedMethod["Contract Address"] == call.contractAddress &&
          allowedMethod.selector == selector.getSelectorFromName(call.entrypoint)
        );
      });
      return tree.getProof(tree.leaves[allowedIndex], leaves);
    });
  }
}

export class MasterCardSigner extends RawSigner {
  constructor(
    public argentX: ArgentX,
    public argentBackend: BackendService,
    public sessionKeyPair: KeyPair,
    public accountSessionSignature: ArraySignatureType,
    public completedSession: OffChainSession,
  ) {
    super();
  }

  public async signRaw(messageHash: string): Promise<ArraySignatureType> {
    return this.sessionKeyPair.signHash(messageHash) as ArraySignatureType;
  }

  // public async signMessage(typedDataArgument: typedData.TypedData, accountAddress: string): Promise<Signature> {
  //   const sessionToken = await this.buildSessiontoken(transactions, transactionsDetail);
  //   return [SESSION_MAGIC, ...CallData.compile({ ...sessionToken })];
  // }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<ArraySignatureType> {
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

  private async signTxAndSession(
    transactionHash: string,
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<StarknetSig> {
    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(this.completedSession),
      transactionsDetail.walletAddress,
    );
    const sessionWithTxHash = ec.starkCurve.pedersen(transactionHash, sessionMessageHash);
    const sessionSig = this.sessionKeyPair.signHash(sessionWithTxHash);
    return {
      r: BigInt(sessionSig[0]),
      s: BigInt(sessionSig[1]),
    };
  }

  private getLeaves(allowedMethods: AllowedMethod[]): string[] {
    return allowedMethods.map((method) =>
      hash.computeHashOnElements([ALLOWED_METHOD_HASH, method["Contract Address"], method.selector]),
    );
  }

  private getSessionProofs(calls: Call[], allowedMethods: AllowedMethod[]): string[][] {
    const tree = new merkle.MerkleTree(this.getLeaves(allowedMethods));

    return calls.map((call) => {
      const allowedIndex = allowedMethods.findIndex((allowedMethod) => {
        return (
          allowedMethod["Contract Address"] == call.contractAddress &&
          allowedMethod.selector == selector.getSelectorFromName(call.entrypoint)
        );
      });
      return tree.getProof(tree.leaves[allowedIndex], this.getLeaves(allowedMethods));
    });
  }
}
