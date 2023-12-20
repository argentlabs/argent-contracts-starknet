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
  SessionToken,
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

  public async getAccountSessionSignature(sessionRequest: OffChainSession): Promise<ArraySignatureType> {
    const sessionTypedData = await getSessionTypedData(sessionRequest);
    return (await this.account.signMessage(sessionTypedData)) as ArraySignatureType;
  }

  public async sendSessionToBackend(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
    sessionRequest: OffChainSession,
  ): Promise<StarknetSig> {
    return this.backendService.signTxAndSession(calls, transactionsDetail, sessionRequest);
  }
}

export class BackendService {
  constructor(public guardian: KeyPair) {}

  public async signTxAndSession(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
    sessionTokenToSign: OffChainSession,
  ): Promise<StarknetSig> {
    // verify session param correct

    // extremely simplified version of the backend verification
    const allowed_methods = sessionTokenToSign.allowed_methods;
    calls.forEach((call) => {
      const found = allowed_methods.find(
        (method) =>
          method["Contract Address"] === call.contractAddress &&
          method.selector === selector.getSelectorFromName(call.entrypoint),
      );
      if (!found) {
        throw new Error("Call not allowed");
      }
    });

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
    public argentX: ArgentX,
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
    const sessionToken = await this.buildSessiontoken(this.completedSession, transactions, transactionsDetail);

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
    const sessionSig = this.sessionKeyPair.signHash(sessionWithTxHash);
    return {
      r: BigInt(sessionSig[0]),
      s: BigInt(sessionSig[1]),
    };
  }

  private async buildSessiontoken(
    completedSession: OffChainSession,
    transactions: Call[],
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<SessionToken> {
    const txHash = await this.getTransactionHash(transactions, transactionsDetail);
    const session_signature = await this.signTxAndSession(txHash, transactionsDetail);
    const backend_signature = await this.getBackendSig(transactions, transactionsDetail);

    const leaves = this.getLeaves(completedSession.allowed_methods);
    const proofs = this.getSessionProofs(transactions, completedSession.allowed_methods);
    const session = {
      expires_at: completedSession.expires_at,
      allowed_methods_root: new merkle.MerkleTree(leaves).root.toString(),
      token_amounts: completedSession.token_amounts,
      nft_contracts: completedSession.nft_contracts,
      max_fee_usage: completedSession.max_fee_usage,
      guardian_key: completedSession.guardian_key,
      session_key: completedSession.session_key,
    };
    return {
      session,
      account_signature: this.accountSessionSignature,
      session_signature,
      backend_signature,
      proofs,
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

  private async getBackendSig(calls: Call[], transactionsDetail: InvocationsSignerDetails): Promise<StarknetSig> {
    return this.argentX.sendSessionToBackend(calls, transactionsDetail, this.completedSession);
  }
}
