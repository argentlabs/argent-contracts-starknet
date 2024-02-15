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
      throw Error("tx v3 not implemented yet"); // TODO
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
    const session = {
      expires_at: completedSession.expires_at,
      allowed_methods_root: this.buildMerkleTree(completedSession).root.toString(),
      token_amounts: completedSession.token_amounts,
      nft_contracts: completedSession.nft_contracts,
      max_fee_usage: completedSession.max_fee_usage,
      guardian_key: completedSession.guardian_key,
      session_key: completedSession.session_key,
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

    const sessionToken = {
      session,
      account_signature: accountSessionSignature,
      session_signature: await this.signTxAndSession(completedSession, transactionHash, accountAddress),
      backend_signature,
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
    const sessionWithTxHash = ec.starkCurve.pedersen(transactionHash, sessionMessageHash);
    const [r, s] = this.sessionKey.signHash(sessionWithTxHash);
    return {
      r: BigInt(r),
      s: BigInt(s),
    };
  }

  private buildMerkleTree(completedSession: OffChainSession): merkle.MerkleTree {
    const leaves = completedSession.allowed_methods.map((method) =>
      hash.computeHashOnElements([
        ALLOWED_METHOD_HASH,
        method["Contract Address"],
        selector.getSelectorFromName(method.selector),
      ]),
    );
    return new merkle.MerkleTree(leaves);
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
}
