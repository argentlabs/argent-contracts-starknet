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
  transaction,
  Account,
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
  ArgentAccount,
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
      new SessionSigner(this.argentBackend, this.sessionKey, accountSessionSignature, completedSession),
      account.cairoVersion,
      account.transactionVersion,
    );
  }

  public async getOutsideExecutionCall(
    completedSession: OffChainSession,
    accountSessionSignature: ArraySignatureType,
    calls: Call[],
    accountAddress: string,
    caller = "ANY_CALLER",
    execute_after = 1,
    execute_before = 999999999999999,
  ): Promise<Call> {
    const sessionSigner = new SessionSigner(
      this.argentBackend,
      this.sessionKey,
      accountSessionSignature,
      completedSession,
    );

    const outsideExecution = {
      caller,
      nonce: randomKeyPair().publicKey,
      execute_after,
      execute_before,
      calls: calls.map((call) => getOutsideCall(call)),
    };
    const signature = await sessionSigner.signOutsideTransaction(calls, accountAddress, outsideExecution);
    return {
      contractAddress: accountAddress,
      entrypoint: "execute_from_outside",
      calldata: CallData.compile({ ...outsideExecution, signature }),
    };
  }
}

class SessionSigner extends RawSigner {
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
      throw Error("tx v3 not implemented yet"); // TODO
    } else {
      throw Error("unsupported signTransaction version");
    }
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
    const session = {
      expires_at: this.completedSession.expires_at,
      allowed_methods_root: this.buildMerkleTree().root.toString(),
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
      proofs: this.getSessionProofs(calls),
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
