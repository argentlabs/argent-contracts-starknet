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
  selector,
  merkle,
  RPC,
  V2InvocationsSignerDetails,
  transaction,
  Account,
  V3InvocationsSignerDetails,
  stark,
  num,
  CairoCustomEnum,
  BigNumberish,
} from "starknet";
import {
  OffChainSession,
  KeyPair,
  randomKeyPair,
  AllowedMethod,
  RawSigner,
  getSessionTypedData,
  ALLOWED_METHOD_HASH,
  getOutsideCall,
  getTypedData,
  provider,
  BackendService,
  ArgentAccount,
  starknetSigner,
  StarknetSig,
  OutsideExecution,
  SignerTypeEnum,
} from ".";

const SESSION_MAGIC = shortString.encodeShortString("session-token");

export class DappService {
  constructor(
    private argentBackend: BackendService,
    public sessionKey: KeyPair = randomKeyPair(),
  ) {}

  public createSessionRequest(
    accountAddress: string,
    allowed_methods: AllowedMethod[],
    expires_at = 150,
  ): OffChainSession {
    const metadata = JSON.stringify({ metadata: "metadata", max_fee: 0 });
    return {
      expires_at,
      allowed_methods,
      metadata,
      backend_key_guid: this.intoGuid(this.argentBackend.getBackendKey(accountAddress), SignerTypeEnum.Starknet),
      session_key_guid: this.intoGuid(this.sessionKey.publicKey, SignerTypeEnum.Starknet),
    };
  }

  public getAccountWithSessionSigner(
    account: ArgentAccount,
    completedSession: OffChainSession,
    accountSessionSignature: ArraySignatureType,
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

      public async signRaw(messageHash: string): Promise<Signature> {
        throw new Error("Method not implemented.");
      }

      public async signTransaction(
        calls: Call[],
        transactionsDetail: InvocationsSignerDetails,
      ): Promise<ArraySignatureType> {
        return this.signTransactionCallback(calls, transactionsDetail);
      }
    })((calls: Call[], transactionsDetail: InvocationsSignerDetails) => {
      return this.signRegularTransaction(accountSessionSignature, completedSession, calls, transactionsDetail);
    });
    return new Account(account, account.address, sessionSigner, account.cairoVersion, account.transactionVersion);
  }

  public async getOutsideExecutionCall(
    completedSession: OffChainSession,
    accountSessionSignature: ArraySignatureType,
    calls: Call[],
    accountAddress: string,
    caller = "ANY_CALLER",
    execute_after = 1,
    execute_before = 999999999999999,
    nonce = randomKeyPair().publicKey,
  ): Promise<Call> {
    const outsideExecution = {
      caller,
      nonce,
      execute_after,
      execute_before,
      calls: calls.map((call) => getOutsideCall(call)),
    };

    const currentTypedData = getTypedData(outsideExecution, await provider.getChainId());
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);
    const signature = await this.compileSessionSignature(
      accountSessionSignature,
      completedSession,
      messageHash,
      calls,
      accountAddress,
      true,
      undefined,
      outsideExecution,
    );

    return {
      contractAddress: accountAddress,
      entrypoint: "execute_from_outside",
      calldata: CallData.compile({ ...outsideExecution, signature }),
    };
  }

  private async signRegularTransaction(
    accountSessionSignature: ArraySignatureType,
    completedSession: OffChainSession,
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<ArraySignatureType> {
    const compiledCalldata = transaction.getExecuteCalldata(calls, transactionsDetail.cairoVersion);
    let txHash;
    if (Object.values(RPC.ETransactionVersion2).includes(transactionsDetail.version as any)) {
      const det = transactionsDetail as V2InvocationsSignerDetails;
      txHash = hash.calculateInvokeTransactionHash({
        ...det,
        senderAddress: det.walletAddress,
        compiledCalldata,
        version: det.version,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(transactionsDetail.version as any)) {
      const det = transactionsDetail as V3InvocationsSignerDetails;
      txHash = hash.calculateInvokeTransactionHash({
        ...det,
        senderAddress: det.walletAddress,
        compiledCalldata,
        version: det.version,
        nonceDataAvailabilityMode: stark.intDAM(det.nonceDataAvailabilityMode),
        feeDataAvailabilityMode: stark.intDAM(det.feeDataAvailabilityMode),
      });
    } else {
      throw Error("unsupported signTransaction version");
    }
    return this.compileSessionSignature(
      accountSessionSignature,
      completedSession,
      txHash,
      calls,
      transactionsDetail.walletAddress,
      false,
      transactionsDetail,
    );
  }

  private async compileSessionSignature(
    accountSessionSignature: ArraySignatureType,
    completedSession: OffChainSession,
    transactionHash: string,
    calls: Call[],
    accountAddress: string,
    isOutside: boolean,
    transactionsDetail?: InvocationsSignerDetails,
    outsideExecution?: OutsideExecution,
  ): Promise<ArraySignatureType> {
    const byteArray = typedData.byteArrayFromString(completedSession.metadata as string);
    const elements = [byteArray.data.length, ...byteArray.data, byteArray.pending_word, byteArray.pending_word_len];
    const metadataHash = hash.computePoseidonHashOnElements(elements);

    const session = {
      expires_at: completedSession.expires_at,
      allowed_methods_root: this.buildMerkleTree(completedSession).root.toString(),
      metadata_hash: metadataHash,
      guardian_key_guid: completedSession.backend_key_guid,
      session_key_guid: completedSession.session_key_guid,
    };

    let backend_signature;

    if (isOutside) {
      backend_signature = await this.argentBackend.signOutsideTxAndSession(
        calls,
        completedSession,
        accountAddress,
        outsideExecution as OutsideExecution,
      );
    } else {
      backend_signature = await this.argentBackend.signTxAndSession(
        calls,
        transactionsDetail as InvocationsSignerDetails,
        completedSession,
      );
    }

    const session_signature = await this.signTxAndSession(completedSession, transactionHash, accountAddress);

    const sessionToken = {
      session,
      session_authorisation: accountSessionSignature,
      session_signature: this.getStarknetSignatureType(
        this.sessionKey.publicKey,
        session_signature.r,
        session_signature.s,
      ),
      backend_signature: this.getStarknetSignatureType(
        this.argentBackend.getBackendKey(accountAddress),
        backend_signature.r,
        backend_signature.s,
      ),
      proofs: this.getSessionProofs(completedSession, calls),
    };
    return [SESSION_MAGIC, ...CallData.compile(sessionToken)];
  }

  private async signTxAndSession(
    completedSession: OffChainSession,
    transactionHash: string,
    accountAddress: string,
  ): Promise<StarknetSig> {
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(completedSession), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHash(transactionHash, sessionMessageHash);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.sessionKey.privateKey));
    return {
      r: BigInt(signature.r),
      s: BigInt(signature.s),
    };
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

  // method needed as starknetSignatureType in signer.ts is already compiled
  private getStarknetSignatureType(signer: BigNumberish, r: bigint, s: bigint) {
    return new CairoCustomEnum({
      Starknet: { signer, r, s },
      Secp256k1: undefined,
      Secp256r1: undefined,
      Webauthn: undefined,
    });
  }

  // method to turn key into guid for now sessions only work with a stark signer
  // but this method should reflect calculating the guid for the signer in signer_signature.cairo
  private intoGuid(signer: BigNumberish, signerType: SignerTypeEnum) {
    if (signerType == SignerTypeEnum.Starknet) {
      return signer;
    } else {
      throw new Error("Not implemented");
    }
  }
}
