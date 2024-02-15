import {
  Account,
  ArraySignatureType,
  Call,
  InvocationsSignerDetails,
  RPC,
  V2InvocationsSignerDetails,
  ec,
  hash,
  num,
  transaction,
  typedData,
} from "starknet";
import {
  KeyPair,
  OffChainSession,
  OutsideExecution,
  StarknetSig,
  getSessionTypedData,
  getTypedData,
  provider,
} from "./";

export class ArgentX {
  constructor(
    public account: Account,
    public backendService: BackendService,
  ) {}

  public async getOffchainSignature(typedData: typedData.TypedData): Promise<ArraySignatureType> {
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
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.guardian.privateKey));
    return { r: BigInt(signature.r), s: BigInt(signature.s) };
  }

  public async signOutsideTxAndSession(
    calls: Call[],
    sessionTokenToSign: OffChainSession,
    accountAddress: string,
    outsideExecution: OutsideExecution,
  ): Promise<StarknetSig> {
    // TODO backend must verify, timestamps fees, used tokens nfts...
    const currentTypedData = getTypedData(outsideExecution, await provider.getChainId());
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);

    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(sessionTokenToSign), accountAddress);
    const sessionWithTxHash = ec.starkCurve.pedersen(messageHash, sessionMessageHash);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.guardian.privateKey));
    return { r: BigInt(signature.r), s: BigInt(signature.s) };
  }

  public getGuardianKey(accountAddress: string): bigint {
    return this.guardian.publicKey;
  }
}
