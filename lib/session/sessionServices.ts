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

export function compileSessionSignature(sessionToken: SessionToken): string[] {
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
    cacheAuthorization = false,
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
    })((calls: Call[], transactionsDetail: InvocationsSignerDetails) => {
      return this.signRegularTransaction(
        sessionAuthorizationSignature,
        completedSession,
        calls,
        transactionsDetail,
        cacheAuthorization,
      );
    });
    return new ArgentAccount(account, account.address, sessionSigner, account.cairoVersion, account.transactionVersion);
  }

  public async getSessionToken(
    calls: Call[],
    account: ArgentAccount,
    completedSession: OffChainSession,
    sessionAuthorizationSignature: ArraySignatureType,
    cacheAuthorization = false,
  ): Promise<SessionToken> {
    const transactionDetail = await getSignerDetails(account, calls);
    const txHash = calculateTransactionHash(transactionDetail, calls);
    return this.buildSessionToken(
      sessionAuthorizationSignature,
      completedSession,
      txHash,
      calls,
      transactionDetail.walletAddress,
      transactionDetail,
      cacheAuthorization,
    );
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
    cacheAuthorization = false,
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
    const signature = await this.compileSessionSignatureFromOutside(
      sessionAuthorizationSignature,
      completedSession,
      messageHash,
      calls,
      accountAddress,
      revision,
      outsideExecution,
      cacheAuthorization,
    );

    return {
      contractAddress: accountAddress,
      entrypoint: revision == TypedDataRevision.ACTIVE ? "execute_from_outside_v2" : "execute_from_outside",
      calldata: CallData.compile({ ...outsideExecution, signature }),
    };
  }

  private async signRegularTransaction(
    sessionAuthorizationSignature: ArraySignatureType,
    completedSession: OffChainSession,
    calls: Call[],
    transactionDetail: InvocationsSignerDetails,
    cacheAuthorization: boolean,
  ): Promise<ArraySignatureType> {
    const txHash = calculateTransactionHash(transactionDetail, calls);
    const sessionToken = await this.buildSessionToken(
      sessionAuthorizationSignature,
      completedSession,
      txHash,
      calls,
      transactionDetail.walletAddress,
      transactionDetail,
      cacheAuthorization,
    );
    return compileSessionSignature(sessionToken);
  }

  private async compileSessionSignatureFromOutside(
    sessionAuthorizationSignature: ArraySignatureType,
    completedSession: OffChainSession,
    transactionHash: string,
    calls: Call[],
    accountAddress: string,
    revision: TypedDataRevision,
    outsideExecution: OutsideExecution,
    cacheAuthorization: boolean,
  ): Promise<ArraySignatureType> {
    const session = this.compileSessionHelper(completedSession);

    const guardianSignature = await this.argentBackend.signOutsideTxAndSession(
      calls,
      completedSession,
      accountAddress,
      outsideExecution as OutsideExecution,
      revision,
      cacheAuthorization,
    );

    const sessionSignature = await this.signTxAndSession(
      completedSession,
      transactionHash,
      accountAddress,
      cacheAuthorization,
    );
    const sessionToken = await this.compileSessionTokenHelper(
      session,
      completedSession,
      calls,
      sessionSignature,
      cacheAuthorization,
      sessionAuthorizationSignature,
      guardianSignature,
      accountAddress,
    );

    return compileSessionSignature(sessionToken);
  }

  private async buildSessionToken(
    sessionAuthorizationSignature: ArraySignatureType,
    completedSession: OffChainSession,
    transactionHash: string,
    calls: Call[],
    accountAddress: string,
    transactionsDetail: InvocationsSignerDetails,
    cacheAuthorization: boolean,
  ): Promise<SessionToken> {
    const session = this.compileSessionHelper(completedSession);

    const guardianSignature = await this.argentBackend.signTxAndSession(
      calls,
      transactionsDetail,
      completedSession,
      cacheAuthorization,
    );
    const session_signature = await this.signTxAndSession(
      completedSession,
      transactionHash,
      accountAddress,
      cacheAuthorization,
    );
    return await this.compileSessionTokenHelper(
      session,
      completedSession,
      calls,
      session_signature,
      cacheAuthorization,
      sessionAuthorizationSignature,
      guardianSignature,
      accountAddress,
    );
  }

  private async signTxAndSession(
    completedSession: OffChainSession,
    transactionHash: string,
    accountAddress: string,
    cacheAuthorization: boolean,
  ): Promise<bigint[]> {
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(completedSession), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      transactionHash,
      sessionMessageHash,
      +cacheAuthorization,
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

  private async compileSessionTokenHelper(
    session: OnChainSession,
    completedSession: OffChainSession,
    calls: Call[],
    sessionSignature: bigint[],
    cache_authorization: boolean,
    session_authorization: string[],
    guardianSignature: bigint[],
    accountAddress: string,
  ): Promise<SessionToken> {
    const sessionContract = await manager.loadContract(accountAddress);
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(completedSession), accountAddress);
    const isSessionCached = await sessionContract.is_session_authorization_cached(
      sessionMessageHash,
      session_authorization,
    );
    return {
      session,
      cache_authorization,
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
