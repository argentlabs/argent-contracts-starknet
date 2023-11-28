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
} from "starknet";
import { OffChainSession, SessionToken, OnChainSession, KeyPair, randomKeyPair, AllowedMethod, TokenLimit, RawSigner, getSessionTypedData, getAllowedMethodRoot} from ".";



export class ArgentX {
  constructor(
    public address: string,
    public backendService: BackendService,
  ) {}

  public sendSessionInitiationToBackend(session: OffChainSession) {
    // return this.backendService.givePublicKeyForSession(session);
  }
}

const SESSION_MAGIC = shortString.encodeShortString("session-token");

export class DappService {
  constructor(public sessionKey: KeyPair = randomKeyPair()) {}

  public createSessionRequestForBackend(
    allowed_methods: AllowedMethod[],
    token_limits: TokenLimit[],
    max_fee_usage = 1_000_000_000_000_000n,
    expires_at = 150,
    nft_contracts: string[] = [],
  ): OffChainSession {
    token_limits.sort((a, b) => (BigInt(a.contract_address) < BigInt(b.contract_address) ? -1 : 1));
    nft_contracts.sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
    return {
      session_key: this.sessionKey.publicKey,
      expires_at,
      allowed_methods,
      max_fee_usage,
      token_limits,
      nft_contracts,
    };
  }

  public get keypair(): KeyPair {
    return this.sessionKey;
  }
}

export class DappSigner extends RawSigner {
  constructor(
    public backendService: BackendService,
    public sessionKeyPair: KeyPair,
    public ownerSessionSignature: bigint[],
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

    const session: OnChainSession = getAllowedMethodRoot(this.completedSession);

    const sessionToken: SessionToken = {
      session,
      session_signature,
      owner_signature: this.ownerSessionSignature,
      backend_signature,
    };

    return [SESSION_MAGIC, ...CallData.compile({ ...sessionToken })];
  }

  public async signTxAndSession(
    transactionHash: string,
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<string[]> {
    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(this.completedSession),
      transactionsDetail.walletAddress,
    );
    const sessionWithTxHash = ec.starkCurve.pedersen(transactionHash, sessionMessageHash);
    return this.sessionKeyPair.signHash(sessionWithTxHash);
  }

  public async getBackendSig(calls: Call[], transactionsDetail: InvocationsSignerDetails): Promise<bigint[]> {
    return this.backendService.signTxAndSession(calls, transactionsDetail, this.completedSession);
  }
}


export class BackendService {
  constructor(public backendKey: KeyPair = randomKeyPair()) {}

  public async signTxAndSession(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
    sessionTokenToSign: OffChainSession,
  ): Promise<bigint[]> {
    // verify session param correct

    // extremely simplified version of the backend verification
    const allowed_methods = sessionTokenToSign.allowed_methods ?? [];
    calls.forEach((call) => {
      const found = allowed_methods.find(
        (method) =>
          method.contract_address === call.contractAddress &&
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
    const [r, s] = this.backendKey.signHash(sessionWithTxHash);
    return [BigInt(r), BigInt(s)];
  }
}

