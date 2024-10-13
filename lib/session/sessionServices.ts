import {
  ArraySignatureType,
  BigNumberish,
  Call,
  CallData,
  InvocationsSignerDetails,
  TypedDataRevision,
  ec,
  hash,
  num,
  typedData,
} from "starknet";
import {
  AllowedMethod,
  ArgentAccount,
  BackendService,
  OutsideExecution,
  RawSigner,
  Session,
  SessionToken,
  SignerType,
  StarknetKeyPair,
  calculateTransactionHash,
  getOutsideCall,
  getSignerDetails,
  getTypedData,
  manager,
  randomStarknetKeyPair,
  signerTypeToCustomEnum,
} from "..";

export class DappService {
  constructor(
    private argentBackend: BackendService,
    public sessionKey: StarknetKeyPair = randomStarknetKeyPair(),
  ) {}

  public createSessionRequest(allowed_methods: AllowedMethod[], expires_at: bigint): Session {
    const metadata = JSON.stringify({ metadata: "metadata", max_fee: 0 });
    return new Session(expires_at, allowed_methods, metadata, this.sessionKey.guid);
  }

  public getAccountWithSessionSigner(
    account: ArgentAccount,
    completedSession: Session,
    authorizationSignature: ArraySignatureType,
    cacheOwnerGuid = 0n,
    isLegacyAccount = false,
  ) {
    const sessionSigner = new (class extends RawSigner {
      constructor(
        private signTransactionCallback: (
          calls: Call[],
          transactionsDetail: InvocationsSignerDetails,
        ) => Promise<ArraySignatureType>,
      ) {
        super();
      }

      public async signRaw(messageHash: string): Promise<string[]> {
        throw new Error("Method not implemented.");
      }

      public async signTransaction(
        calls: Call[],
        transactionsDetail: InvocationsSignerDetails,
      ): Promise<ArraySignatureType> {
        return this.signTransactionCallback(calls, transactionsDetail);
      }
    })((calls: Call[], transactionDetail: InvocationsSignerDetails) => {
      return this.signRegularTransaction({
        authorizationSignature,
        completedSession,
        calls,
        transactionDetail,
        cacheOwnerGuid,
        isLegacyAccount,
      });
    });
    return new ArgentAccount(account, account.address, sessionSigner, account.cairoVersion, account.transactionVersion);
  }

  public async getSessionToken(arg: {
    calls: Call[];
    account: ArgentAccount;
    completedSession: Session;
    authorizationSignature: ArraySignatureType;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<SessionToken> {
    const { calls, account, completedSession, authorizationSignature, cacheOwnerGuid, isLegacyAccount } = arg;
    const transactionDetail = await getSignerDetails(account, calls);
    const txHash = calculateTransactionHash(transactionDetail, calls);
    return this.buildSessionToken({
      authorizationSignature,
      completedSession,
      transactionHash: txHash,
      calls,
      accountAddress: transactionDetail.walletAddress,
      transactionDetail,
      cacheOwnerGuid,
      isLegacyAccount,
    });
  }

  public async getOutsideExecutionCall(
    completedSession: Session,
    authorizationSignature: ArraySignatureType,
    calls: Call[],
    revision: TypedDataRevision,
    accountAddress: string,
    caller = "ANY_CALLER",
    execute_after = 1,
    execute_before = 999999999999999,
    nonce = randomStarknetKeyPair().publicKey,
    cacheOwnerGuid = 0n,
    isLegacyAccount = false,
  ): Promise<Call> {
    const outsideExecution = {
      caller,
      nonce,
      execute_after,
      execute_before,
      calls: calls.map((call) => getOutsideCall(call)),
    };

    const currentTypedData = getTypedData(outsideExecution, await manager.getChainId(), revision);
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);
    const signature = await this.compileSessionSignatureFromOutside({
      authorizationSignature,
      completedSession,
      transactionHash: messageHash,
      calls,
      accountAddress,
      revision,
      outsideExecution,
      cacheOwnerGuid,
      isLegacyAccount,
    });

    return {
      contractAddress: accountAddress,
      entrypoint: revision == TypedDataRevision.ACTIVE ? "execute_from_outside_v2" : "execute_from_outside",
      calldata: CallData.compile({ ...outsideExecution, signature }),
    };
  }

  private async signRegularTransaction(args: {
    authorizationSignature: ArraySignatureType;
    completedSession: Session;
    calls: Call[];
    transactionDetail: InvocationsSignerDetails;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<ArraySignatureType> {
    const { authorizationSignature, completedSession, calls, transactionDetail, cacheOwnerGuid, isLegacyAccount } =
      args;
    const txHash = calculateTransactionHash(transactionDetail, calls);
    const sessionToken = await this.buildSessionToken({
      authorizationSignature,
      completedSession,
      transactionHash: txHash,
      calls,
      accountAddress: transactionDetail.walletAddress,
      transactionDetail,
      cacheOwnerGuid,
      isLegacyAccount,
    });
    return sessionToken.compileSignature();
  }

  private async compileSessionSignatureFromOutside(args: {
    authorizationSignature: ArraySignatureType;
    completedSession: Session;
    transactionHash: string;
    calls: Call[];
    accountAddress: string;
    revision: TypedDataRevision;
    outsideExecution: OutsideExecution;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<ArraySignatureType> {
    const {
      authorizationSignature,
      completedSession,
      transactionHash,
      calls,
      accountAddress,
      revision,
      outsideExecution,
      cacheOwnerGuid,
      isLegacyAccount,
    } = args;

    const guardianSignature = await this.argentBackend.signOutsideTxAndSession(
      calls,
      completedSession,
      accountAddress,
      outsideExecution as OutsideExecution,
      revision,
      cacheOwnerGuid,
    );

    const sessionSignature = await this.signTxAndSession(
      completedSession,
      transactionHash,
      accountAddress,
      cacheOwnerGuid,
      isLegacyAccount,
    );

    const sessionToken = await SessionToken.build({
      session: completedSession,
      cache_owner_guid: cacheOwnerGuid,
      session_authorization: authorizationSignature,
      session_signature: this.getStarknetSignatureType(this.sessionKey.publicKey, sessionSignature),
      guardian_signature: this.getStarknetSignatureType(
        this.argentBackend.getBackendKey(accountAddress),
        guardianSignature,
      ),
      calls,
      isLegacyAccount,
    });

    return sessionToken.compileSignature();
  }

  private async buildSessionToken(args: {
    authorizationSignature: ArraySignatureType;
    completedSession: Session;
    transactionHash: string;
    calls: Call[];
    accountAddress: string;
    transactionDetail: InvocationsSignerDetails;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<SessionToken> {
    const {
      authorizationSignature,
      completedSession,
      transactionHash,
      calls,
      accountAddress,
      transactionDetail,
      cacheOwnerGuid,
      isLegacyAccount,
    } = args;
    const guardianSignature = await this.argentBackend.signTxAndSession(
      calls,
      transactionDetail,
      completedSession,
      cacheOwnerGuid,
      isLegacyAccount,
    );
    const sessionSignature = await this.signTxAndSession(
      completedSession,
      transactionHash,
      accountAddress,
      cacheOwnerGuid,
      isLegacyAccount,
    );
    const isSessionCached = await completedSession.isSessionCached(accountAddress, cacheOwnerGuid, isLegacyAccount);
    return await SessionToken.build({
      session: completedSession,
      cache_owner_guid: cacheOwnerGuid,
      session_authorization: isSessionCached ? [] : authorizationSignature,
      session_signature: this.getStarknetSignatureType(this.sessionKey.publicKey, sessionSignature),
      guardian_signature: this.getStarknetSignatureType(
        this.argentBackend.getBackendKey(accountAddress),
        guardianSignature,
      ),
      calls,
      isLegacyAccount,
    });
  }

  private async signTxAndSession(
    completedSession: Session,
    transactionHash: string,
    accountAddress: string,
    cacheOwnerGuid: bigint,
    isLegacyAccount: boolean,
  ): Promise<bigint[]> {
    const sessionMessageHash = typedData.getMessageHash(await completedSession.getTypedData(), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      transactionHash,
      sessionMessageHash,
      isLegacyAccount ? +(cacheOwnerGuid !== 0n) : cacheOwnerGuid,
    ]);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.sessionKey.privateKey));
    return [signature.r, signature.s];
  }
  // function needed as starknetSignatureType in signer.ts is already compiled
  private getStarknetSignatureType(pubkey: BigNumberish, signature: bigint[]) {
    return signerTypeToCustomEnum(SignerType.Starknet, { pubkey, r: signature[0], s: signature[1] });
  }
}
