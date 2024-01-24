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
  RPC,
  V2InvocationsSignerDetails,
  TypedData,
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
  ArgentAccount,
} from ".";

const SESSION_MAGIC = shortString.encodeShortString("session-token");

export class ArgentX {
  constructor(
    public account: Account,
    public backendService: BackendService,
  ) {}

  public async getOffchainSignature(typedData: TypedData): Promise<ArraySignatureType> {
    // autosigning for PoC, in real live there would be some checks by the extension and by the backend
    return (await this.account.signMessage(typedData)) as ArraySignatureType;
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
    // backend must check, timestamps fees, used tokens nfts...
    const allowed_methods = sessionTokenToSign.allowed_methods;
    if (
      !calls.every((call) => {
        return allowed_methods.some(
          (method) => method["Contract Address"] === call.contractAddress && method.selector === call.entrypoint,
        );
      })
    ) {
      throw new Error("Call not allowed by guardian");
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

  public getGuardianKey(accountAddress: string): bigint {
    return this.guardian.publicKey;
  }
}

export class DappService {
  constructor(
    private argentBackend: BackendService,
    public sessionKey: KeyPair = randomKeyPair(),
  ) {}

  public createSessionRequest(
    accountAddress: string,
    allowed_methods: AllowedMethod[],
    token_amounts: TokenAmount[],
    expires_at = 150,
    max_fee_usage = { token_address: "0x0", amount: uint256.bnToUint256(1000000n) },
    nft_contracts: string[] = [],
  ): OffChainSession {
    return {
      expires_at,
      allowed_methods,
      token_amounts,
      nft_contracts,
      max_fee_usage,
      guardian_key: this.argentBackend.getGuardianKey(accountAddress),
      session_key: this.sessionKey.publicKey,
    };
  }

  public getAccountWithSessionSigner(
    account: ArgentAccount,
    completedSession: OffChainSession,
    accountSessionSignature: ArraySignatureType,
  ) {
    return new Account(
      account,
      account.address,
      new DappSigner(this.argentBackend, this.sessionKey, accountSessionSignature, completedSession),
      account.cairoVersion,
      account.transactionVersion,
    );
  }
}

class DappSigner extends RawSigner {
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
    calls: Call[],
    transactionsDetail: InvocationsSignerDetails,
  ): Promise<ArraySignatureType> {
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
      throw Error("tx v3 not implemented yet"); // TODO
    } else {
      throw Error("unsupported signTransaction version");
    }

    const session = {
      expires_at: this.completedSession.expires_at,
      allowed_methods_root: this.buildMerkleTree().root.toString(),
      token_amounts: this.completedSession.token_amounts,
      nft_contracts: this.completedSession.nft_contracts,
      max_fee_usage: this.completedSession.max_fee_usage,
      guardian_key: this.completedSession.guardian_key,
      session_key: this.completedSession.session_key,
    };

    const sessionToken = {
      session,
      account_signature: this.accountSessionSignature,
      session_signature: await this.signTxAndSession(msgHash, transactionsDetail),
      backend_signature: await this.argentBackend.signTxAndSession(calls, transactionsDetail, this.completedSession),
      proofs: this.getSessionProofs(calls),
    };

    return [SESSION_MAGIC, ...CallData.compile(sessionToken)];
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

  private buildMerkleTree(): merkle.MerkleTree {
    const leaves = this.completedSession.allowed_methods.map((method) =>
      hash.computeHashOnElements([
        ALLOWED_METHOD_HASH,
        method["Contract Address"],
        selector.getSelectorFromName(method.selector),
      ]),
    );
    return new merkle.MerkleTree(leaves);
  }

  private getSessionProofs(calls: Call[]): string[][] {
    const tree = this.buildMerkleTree();

    return calls.map((call) => {
      const allowedIndex = this.completedSession.allowed_methods.findIndex((allowedMethod) => {
        return allowedMethod["Contract Address"] == call.contractAddress && allowedMethod.selector == call.entrypoint;
      });
      return tree.getProof(tree.leaves[allowedIndex], tree.leaves);
    });
  }
}
