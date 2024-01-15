import { OutsideExecution } from "./outsideExecution";
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
  uint256,
  merkle,
  RPC,
  V2InvocationsSignerDetails,
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
  getOutsideCall,
  getTypedData,
  provider,
  BackendService,
} from ".";

const SESSION_MAGIC = shortString.encodeShortString("session-token");

<<<<<<< HEAD
=======
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

    const compiledCalldata = transaction.getExecuteCalldata(calls, transactionsDetail.cairoVersion);
    let msgHash;
    if (Object.values(RPC.ETransactionVersion2).includes(transactionsDetail.version as any)) {
      const det = transactionsDetail as V2InvocationsSignerDetails;
      msgHash = hash.calculateInvokeTransactionHash({
        ...det,
        senderAddress: det.walletAddress,
        compiledCalldata,
        version: det.version,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(transactionsDetail.version as any)) {
      throw Error("not implemented");
    } else {
      throw Error("unsupported signTransaction version");
    }

    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(sessionTokenToSign),
      transactionsDetail.walletAddress,
    );
    const sessionWithTxHash = ec.starkCurve.pedersen(msgHash, sessionMessageHash);
    const [r, s] = this.guardian.signHash(sessionWithTxHash);
    return { r: BigInt(r), s: BigInt(s) };
  }

  public getGuardianKey(): bigint {
    return this.guardian.publicKey;
  }
}

>>>>>>> feat/hybrid-onchain
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
}

export class SessionSigner extends RawSigner {
  constructor(
    public argentBackend: BackendService,
    public sessionKeyPair: KeyPair,
    public accountSessionSignature: ArraySignatureType,
    public completedSession: OffChainSession,
  ) {
    super();
  }

  public async signRaw(messageHash: string): Promise<Signature> {
    return this.sessionKeyPair.signHash(messageHash);
  }

  public async getOutisdeExecutionCall(
    calls: Call[],
    accountAddress: string,
    caller = "ANY_CALLER",
    execute_after = 1,
    execute_before = 999999999999999,
  ): Promise<Call> {
    const outsideExecution = {
      caller,
      nonce: randomKeyPair().publicKey,
      execute_after,
      execute_before,
      calls: calls.map((call) => getOutsideCall(call)),
    };
    const signature = await this.signOutsideTransaction(calls, accountAddress, outsideExecution);
    return {
      contractAddress: accountAddress,
      entrypoint: "execute_from_outside",
      calldata: CallData.compile({ ...outsideExecution, signature }),
    };
  }

  public async signOutsideTransaction(
    calls: Call[],
    accountAddress: string,
    outsideExecution: OutsideExecution,
  ): Promise<Signature> {
    const currentTypedData = getTypedData(outsideExecution, await provider.getChainId());
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);
    return this.compileSessionSignature(messageHash, calls, accountAddress, true, undefined, outsideExecution);
  }

  public async signTransaction(
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<ArraySignatureType> {
<<<<<<< HEAD
    const txHash = await this.getTransactionHash(calls, transactionsDetail);
    return this.compileSessionSignature(txHash, calls, transactionsDetail.walletAddress, false, transactionsDetail);
  }

  private async compileSessionSignature(
    transactionHash: string,
    calls: Call[],
    accountAddress: string,
    isOutside: boolean,
    transactionsDetail?: InvocationsSignerDetails,
    outsideExecution?: OutsideExecution,
  ): Promise<ArraySignatureType> {
=======
    const compiledCalldata = transaction.getExecuteCalldata(calls, transactionsDetail.cairoVersion);
    let msgHash;
    if (Object.values(RPC.ETransactionVersion2).includes(transactionsDetail.version as any)) {
      const det = transactionsDetail as V2InvocationsSignerDetails;
      msgHash = hash.calculateInvokeTransactionHash({
        ...det,
        senderAddress: det.walletAddress,
        compiledCalldata,
        version: det.version,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(transactionsDetail.version as any)) {
      throw Error("not implemented");
    } else {
      throw Error("unsupported signTransaction version");
    }

>>>>>>> feat/hybrid-onchain
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

    let backend_signature;

    if (isOutside) {
      backend_signature = await this.argentBackend.signOutsideTxAndSession(
        calls,
        this.completedSession,
        accountAddress,
        outsideExecution as OutsideExecution,
      );
    } else {
      backend_signature = await this.argentBackend.signTxAndSession(
        calls,
        transactionsDetail as InvocationsSignerDetails,
        this.completedSession,
      );
    }

    const sessionToken = {
      session,
      account_signature: this.accountSessionSignature,
<<<<<<< HEAD
      session_signature: await this.signTxAndSession(transactionHash, accountAddress),
      backend_signature,
=======
      session_signature: await this.signTxAndSession(msgHash, transactionsDetail),
      backend_signature: await this.argentBackend.signTxAndSession(calls, transactionsDetail, this.completedSession),
>>>>>>> feat/hybrid-onchain
      proofs: this.getSessionProofs(calls, this.completedSession.allowed_methods, leaves),
    };

    return [SESSION_MAGIC, ...CallData.compile(sessionToken)];
  }

  private async signTxAndSession(transactionHash: string, accountAddress: string): Promise<StarknetSig> {
    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(this.completedSession),
      accountAddress,
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
