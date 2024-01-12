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
  transaction,
  selector,
  Account,
  uint256,
  merkle,
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
} from ".";

const SESSION_MAGIC = shortString.encodeShortString("session-token");

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

  public async signOutsideTxAndSession(
    calls: Call[],
    sessionTokenToSign: OffChainSession,
    accountAddress: string,
    outsideExecution: OutsideExecution,
  ): Promise<StarknetSig> {
    const currentTypedData = getTypedData(outsideExecution, await provider.getChainId());
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);

    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(sessionTokenToSign), accountAddress);
    const sessionWithTxHash = ec.starkCurve.pedersen(messageHash, sessionMessageHash);
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

  public getOustideExecutionStruct(calls: Call[]): OutsideExecution {
    return {
      caller: "ANY_CALLER",
      nonce: randomKeyPair().publicKey,
      execute_after: 1,
      execute_before: 999999999999999,
      calls: calls.map((call) => getOutsideCall(call)),
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
      session_signature: await this.signTxAndSession(transactionHash, accountAddress),
      backend_signature,
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
