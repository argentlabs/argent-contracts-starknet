import {
  ArraySignatureType,
  BigNumberish,
  Call,
  CallData,
  InvocationsSignerDetails,
  TypedDataRevision,
  ec,
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

  public createSessionRequest(
    allowed_methods: AllowedMethod[],
    expires_at: bigint,
    isLegacyAccount = false,
  ): Session {
    const metadata = JSON.stringify({ metadata: "metadata", max_fee: 0 });
    return new Session(expires_at, allowed_methods, metadata, this.sessionKey.guid, isLegacyAccount);
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
      // needs to return a promise otherwise it will fail
      return new Promise(async (resolve, reject) => {
        try {
          const sessionToken = await this.getSessionToken({
            calls,
            account,
            completedSession,
            authorizationSignature,
            cacheOwnerGuid,
            isLegacyAccount,
            transactionDetail,
          });
          const signature = sessionToken.compileSignature();
          resolve(signature);
        } catch (error) {
          reject(error);
        }
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
    transactionDetail?: InvocationsSignerDetails;
  }): Promise<SessionToken> {
    const {
      calls,
      account,
      completedSession,
      authorizationSignature,
      cacheOwnerGuid,
      isLegacyAccount,
      transactionDetail: providedTransactionDetail,
    } = arg;

    let transactionDetail: InvocationsSignerDetails;
    if (providedTransactionDetail) {
      transactionDetail = providedTransactionDetail;
    } else {
      transactionDetail = await getSignerDetails(account, calls);
    }

    const transactionHash = calculateTransactionHash(transactionDetail, calls);
    const accountAddress = transactionDetail.walletAddress;

    const { sessionSignature, guardianSignature } = await this.generateSessionSignatures({
      completedSession,
      transactionHash,
      calls,
      accountAddress,
      cacheOwnerGuid,
      transactionDetail,
    });

    const isSessionCached = await completedSession.isSessionCached(accountAddress, cacheOwnerGuid);

    return new SessionToken({
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

    const { sessionSignature, guardianSignature } = await this.generateSessionSignatures({
      completedSession,
      transactionHash: messageHash,
      calls,
      accountAddress,
      cacheOwnerGuid,
      outsideExecution,
      revision,
    });
    const sessionToken = new SessionToken({
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

    const compiledSignature = sessionToken.compileSignature();
    return {
      contractAddress: accountAddress,
      entrypoint: revision == TypedDataRevision.ACTIVE ? "execute_from_outside_v2" : "execute_from_outside",
      calldata: CallData.compile({ ...outsideExecution, compiledSignature }),
    };
  }

  private async generateSessionSignatures(args: {
    completedSession: Session;
    transactionHash: string;
    calls: Call[];
    accountAddress: string;
    cacheOwnerGuid: bigint;
    transactionDetail?: InvocationsSignerDetails;
    outsideExecution?: OutsideExecution;
    revision?: TypedDataRevision;
  }): Promise<{
    sessionSignature: bigint[];
    guardianSignature: bigint[];
  }> {
    const {
      completedSession,
      transactionHash,
      calls,
      accountAddress,
      cacheOwnerGuid,
      transactionDetail,
      outsideExecution,
      revision,
    } = args;

    let guardianSignature: bigint[];

    if (outsideExecution && revision) {
      guardianSignature = await this.argentBackend.signOutsideTxAndSession(
        calls,
        completedSession,
        accountAddress,
        outsideExecution,
        revision,
        cacheOwnerGuid,
      );
    } else if (transactionDetail) {
      guardianSignature = await this.argentBackend.signTxAndSession(
        calls,
        transactionDetail,
        completedSession,
        cacheOwnerGuid,
      );
    } else {
      throw new Error("Invalid arguments: either outsideExecution and revision, or transactionDetail must be provided");
    }

    const sessionSignature = await this.signTxAndSession(
      completedSession,
      transactionHash,
      accountAddress,
      cacheOwnerGuid,
    );

    return {
      sessionSignature,
      guardianSignature,
    };
  }

  private async signTxAndSession(
    completedSession: Session,
    transactionHash: string,
    accountAddress: string,
    cacheOwnerGuid: bigint,
  ): Promise<bigint[]> {
    const sessionWithTxHash = await completedSession.hashWithTransaction(
      transactionHash,
      accountAddress,
      cacheOwnerGuid,
    );
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.sessionKey.privateKey));
    return [signature.r, signature.s];
  }
  // function needed as starknetSignatureType in signer.ts is already compiled
  private getStarknetSignatureType(pubkey: BigNumberish, signature: bigint[]) {
    return signerTypeToCustomEnum(SignerType.Starknet, { pubkey, r: signature[0], s: signature[1] });
  }
}
