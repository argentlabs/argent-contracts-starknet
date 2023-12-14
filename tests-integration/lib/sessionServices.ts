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
} from "starknet";
import {
  OffChainSession,
  SessionToken,
  OnChainSession,
  KeyPair,
  randomKeyPair,
  AllowedMethod,
  TokenAmount,
  RawSigner,
  getSessionTypedData,
  createOnChainSession,
  getSessionProofs,
  BasicSignature,
} from ".";

const SESSION_MAGIC = shortString.encodeShortString("session-token");

export class ArgentX {
  constructor(
    public account: Account,
    public backendService: BackendService,
  ) {}

  public async getOwnerSessionSignature(sessionRequest: OffChainSession): Promise<BasicSignature> {
    const sessionTypedData = await getSessionTypedData(sessionRequest);
    const a = (await this.account.signMessage(sessionTypedData)) as ArraySignatureType;
    return { r: BigInt(a[0]), s: BigInt(a[1]) };
  }

  public async sendSessionToBackend(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
    sessionRequest: OffChainSession,
  ): Promise<BasicSignature> {
    return this.backendService.signTxAndSession(calls, transactionsDetail, sessionRequest);
  }
}

export class BackendService {
  constructor(public guardian: KeyPair) {}

  public async signTxAndSession(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
    sessionTokenToSign: OffChainSession,
  ): Promise<BasicSignature> {
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

    // now use abi to display decoded data somewhere, but as this signer is headless, we can't do that
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

  public get_guardian_key(): bigint {
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
    token_limits: TokenAmount[],
    expires_at = 150,
    max_fee_usage = 1_000_000_000_000_000n,
    nft_contracts: string[] = [],
  ): OffChainSession {
    token_limits.sort((a, b) => (BigInt(a.token_address) < BigInt(b.token_address) ? -1 : 1));
    nft_contracts.sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
    return {
      expires_at,
      allowed_methods,
      token_limits,
      max_fee_usage,
      guardian_key: this.argentBackend.get_guardian_key(),
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
    public ownerSessionSignature: BasicSignature,
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
    const session_signature = await this.signTxAndSession(txHash, transactionsDetail);
    const backend_signature = await this.getBackendSig(transactions, transactionsDetail);

    const proofs = await this.getProofs(transactions);

    const session: OnChainSession = createOnChainSession(this.completedSession);

    const sessionToken: SessionToken = {
      session,
      session_signature,
      owner_signature: this.ownerSessionSignature,
      backend_signature,
      proofs,
    };

    return [SESSION_MAGIC, ...CallData.compile({ ...sessionToken })];
  }

  async signTxAndSession(
    transactionHash: string,
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<BasicSignature> {
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

  public async getBackendSig(calls: Call[], transactionsDetail: InvocationsSignerDetails): Promise<BasicSignature> {
    return this.argentX.sendSessionToBackend(calls, transactionsDetail, this.completedSession);
  }

  public async getProofs(transactions: Call[]): Promise<string[][]> {
    return getSessionProofs(transactions, this.completedSession.allowed_methods);
  }
}
