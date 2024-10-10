import {
  ArraySignatureType,
  BigNumberish,
  Call,
  CallData,
  InvocationsSignerDetails,
  TypedDataRevision,
  byteArray,
  ec,
  hash,
  merkle,
  num,
  selector,
  shortString,
  typedData,
} from "starknet";
import {
  ALLOWED_METHOD_HASH,
  AllowedMethod,
  ArgentAccount,
  BackendService,
  OffChainSession,
  OnChainSession,
  OutsideExecution,
  RawSigner,
  SessionToken,
  SignerType,
  StarknetKeyPair,
  calculateTransactionHash,
  getOutsideCall,
  getSessionTypedData,
  getSignerDetails,
  getTypedData,
  manager,
  randomStarknetKeyPair,
  signerTypeToCustomEnum,
} from "..";

export function compileSessionSignature(sessionToken: any): string[] {
  const SESSION_MAGIC = shortString.encodeShortString("session-token");
  return [SESSION_MAGIC, ...CallData.compile({ sessionToken })];
}

export class DappService {
  constructor(
    private argentBackend: BackendService,
    public sessionKey: StarknetKeyPair = randomStarknetKeyPair(),
  ) {}

  public createSessionRequest(allowed_methods: AllowedMethod[], expires_at: bigint): OffChainSession {
    const metadata = JSON.stringify({ metadata: "metadata", max_fee: 0 });
    return {
      expires_at: Number(expires_at),
      allowed_methods,
      metadata,
      session_key_guid: this.sessionKey.guid,
    };
  }

  public getAccountWithSessionSigner(
    account: ArgentAccount,
    completedSession: OffChainSession,
    sessionAuthorizationSignature: ArraySignatureType,
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
        sessionAuthorizationSignature,
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
    completedSession: OffChainSession;
    sessionAuthorizationSignature: ArraySignatureType;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<SessionToken> {
    const { calls, account, completedSession, sessionAuthorizationSignature, cacheOwnerGuid, isLegacyAccount } = arg;
    const transactionDetail = await getSignerDetails(account, calls);
    const txHash = calculateTransactionHash(transactionDetail, calls);
    return this.buildSessionToken({
      sessionAuthorizationSignature,
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
    completedSession: OffChainSession,
    sessionAuthorizationSignature: ArraySignatureType,
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
      sessionAuthorizationSignature,
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
    sessionAuthorizationSignature: ArraySignatureType;
    completedSession: OffChainSession;
    calls: Call[];
    transactionDetail: InvocationsSignerDetails;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<ArraySignatureType> {
    const {
      sessionAuthorizationSignature,
      completedSession,
      calls,
      transactionDetail,
      cacheOwnerGuid,
      isLegacyAccount,
    } = args;
    const txHash = calculateTransactionHash(transactionDetail, calls);
    const sessionToken = await this.buildSessionToken({
      sessionAuthorizationSignature,
      completedSession,
      transactionHash: txHash,
      calls,
      accountAddress: transactionDetail.walletAddress,
      transactionDetail,
      cacheOwnerGuid,
      isLegacyAccount,
    });
    return compileSessionSignature(sessionToken);
  }

  private async compileSessionSignatureFromOutside(args: {
    sessionAuthorizationSignature: ArraySignatureType;
    completedSession: OffChainSession;
    transactionHash: string;
    calls: Call[];
    accountAddress: string;
    revision: TypedDataRevision;
    outsideExecution: OutsideExecution;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<ArraySignatureType> {
    const {
      sessionAuthorizationSignature,
      completedSession,
      transactionHash,
      calls,
      accountAddress,
      revision,
      outsideExecution,
      cacheOwnerGuid,
      isLegacyAccount,
    } = args;
    const session = this.compileSessionHelper(completedSession);

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
    const sessionToken = await this.compileSessionTokenHelper({
      session,
      completedSession,
      calls,
      sessionSignature,
      cache_owner_guid: cacheOwnerGuid,
      isLegacyAccount,
      session_authorization: sessionAuthorizationSignature,
      guardianSignature,
      accountAddress,
    });

    return compileSessionSignature(sessionToken);
  }

  private async buildSessionToken(args: {
    sessionAuthorizationSignature: ArraySignatureType;
    completedSession: OffChainSession;
    transactionHash: string;
    calls: Call[];
    accountAddress: string;
    transactionDetail: InvocationsSignerDetails;
    cacheOwnerGuid: bigint;
    isLegacyAccount: boolean;
  }): Promise<SessionToken> {
    const {
      sessionAuthorizationSignature,
      completedSession,
      transactionHash,
      calls,
      accountAddress,
      transactionDetail,
      cacheOwnerGuid,
      isLegacyAccount,
    } = args;
    const session = this.compileSessionHelper(completedSession);

    const guardianSignature = await this.argentBackend.signTxAndSession(
      calls,
      transactionDetail,
      completedSession,
      cacheOwnerGuid,
      isLegacyAccount,
    );
    const session_signature = await this.signTxAndSession(
      completedSession,
      transactionHash,
      accountAddress,
      cacheOwnerGuid,
      isLegacyAccount,
    );
    return await this.compileSessionTokenHelper({
      session,
      completedSession,
      calls,
      sessionSignature: session_signature,
      isLegacyAccount,
      cache_owner_guid: cacheOwnerGuid,
      session_authorization: sessionAuthorizationSignature,
      guardianSignature,
      accountAddress,
    });
  }

  private async signTxAndSession(
    completedSession: OffChainSession,
    transactionHash: string,
    accountAddress: string,
    cacheOwnerGuid: bigint,
    isLegacyAccount: boolean,
  ): Promise<bigint[]> {
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(completedSession), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      transactionHash,
      sessionMessageHash,
      isLegacyAccount ? +(cacheOwnerGuid !== 0n) : cacheOwnerGuid,
    ]);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.sessionKey.privateKey));
    return [signature.r, signature.s];
  }

  private buildMerkleTree(completedSession: OffChainSession): merkle.MerkleTree {
    const leaves = completedSession.allowed_methods.map((method) =>
      hash.computePoseidonHashOnElements([
        ALLOWED_METHOD_HASH,
        method["Contract Address"],
        selector.getSelectorFromName(method.selector),
      ]),
    );
    return new merkle.MerkleTree(leaves, hash.computePoseidonHash);
  }

  private getSessionProofs(completedSession: OffChainSession, calls: Call[]): string[][] {
    const tree = this.buildMerkleTree(completedSession);

    return calls.map((call) => {
      const allowedIndex = completedSession.allowed_methods.findIndex((allowedMethod) => {
        return allowedMethod["Contract Address"] == call.contractAddress && allowedMethod.selector == call.entrypoint;
      });
      return tree.getProof(tree.leaves[allowedIndex], tree.leaves);
    });
  }

  private compileSessionHelper(completedSession: OffChainSession): OnChainSession {
    const bArray = byteArray.byteArrayFromString(completedSession.metadata as string);
    const elements = [bArray.data.length, ...bArray.data, bArray.pending_word, bArray.pending_word_len];
    const metadataHash = hash.computePoseidonHashOnElements(elements);

    const session = {
      expires_at: completedSession.expires_at,
      allowed_methods_root: this.buildMerkleTree(completedSession).root.toString(),
      metadata_hash: metadataHash,
      session_key_guid: completedSession.session_key_guid,
    };
    return session;
  }

  private async compileSessionTokenHelper(args: {
    session: OnChainSession;
    completedSession: OffChainSession;
    calls: Call[];
    sessionSignature: bigint[];
    cache_owner_guid: bigint;
    isLegacyAccount: boolean;
    session_authorization: string[];
    guardianSignature: bigint[];
    accountAddress: string;
  }): Promise<SessionToken> {
    const {
      session,
      completedSession,
      calls,
      sessionSignature,
      cache_owner_guid,
      isLegacyAccount,
      session_authorization,
      guardianSignature,
      accountAddress,
    } = args;
    const sessionContract = await manager.loadContract(accountAddress);
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(completedSession), accountAddress);
    const isSessionCached = isLegacyAccount
      ? await sessionContract.is_session_authorization_cached(sessionMessageHash)
      : await sessionContract.is_session_authorization_cached(sessionMessageHash, cache_owner_guid);
    return {
      session,
      cache_owner_guid,
      session_authorization: isSessionCached ? [] : session_authorization,
      session_signature: this.getStarknetSignatureType(this.sessionKey.publicKey, sessionSignature),
      guardian_signature: this.getStarknetSignatureType(
        this.argentBackend.getBackendKey(accountAddress),
        guardianSignature,
      ),
      proofs: this.getSessionProofs(completedSession, calls),
    };
  }

  // function needed as starknetSignatureType in signer.ts is already compiled
  private getStarknetSignatureType(pubkey: BigNumberish, signature: bigint[]) {
    return signerTypeToCustomEnum(SignerType.Starknet, { pubkey, r: signature[0], s: signature[1] });
  }
}
