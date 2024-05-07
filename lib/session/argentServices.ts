import {
  Account,
  ArraySignatureType,
  Call,
  InvocationsSignerDetails,
  RPC,
  V2InvocationsSignerDetails,
  V3InvocationsSignerDetails,
  ec,
  hash,
  num,
  stark,
  transaction,
  typedData,
} from "starknet";
import { OffChainSession, OutsideExecution, StarknetKeyPair, getSessionTypedData, getTypedData, provider } from "..";

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
  // TODO We might want to update this to support KeyPair instead of StarknetKeyPair?
  // Or that backend becomes: "export class BackendService extends KeyPair {", can also extends RawSigner ?
  constructor(private backendKey: StarknetKeyPair) {}

  public async signTxAndSession(
    calls: Call[],
    transactionDetail: InvocationsSignerDetails,
    sessionTokenToSign: OffChainSession,
    cacheAuthorization: boolean,
  ): Promise<bigint[]> {
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
      throw new Error("Call not allowed by backend");
    }

    const compiledCalldata = transaction.getExecuteCalldata(calls, transactionDetail.cairoVersion);
    let msgHash;
    if (Object.values(RPC.ETransactionVersion2).includes(transactionDetail.version as any)) {
      const transactionDetailV2 = transactionDetail as V2InvocationsSignerDetails;
      msgHash = hash.calculateInvokeTransactionHash({
        ...transactionDetailV2,
        senderAddress: transactionDetailV2.walletAddress,
        compiledCalldata,
      });
    } else if (Object.values(RPC.ETransactionVersion3).includes(transactionDetail.version as any)) {
      const transactionDetailV3 = transactionDetail as V3InvocationsSignerDetails;
      msgHash = hash.calculateInvokeTransactionHash({
        ...transactionDetailV3,
        senderAddress: transactionDetailV3.walletAddress,
        compiledCalldata,
        nonceDataAvailabilityMode: stark.intDAM(transactionDetailV3.nonceDataAvailabilityMode),
        feeDataAvailabilityMode: stark.intDAM(transactionDetailV3.feeDataAvailabilityMode),
      });
    } else {
      throw Error("unsupported signTransaction version");
    }

    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(sessionTokenToSign),
      transactionDetail.walletAddress,
    );
    const sessionWithTxHash = hash.computePoseidonHashOnElements([msgHash, sessionMessageHash, +cacheAuthorization]);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.backendKey.privateKey));
    return [signature.r, signature.s];
  }

  public async signOutsideTxAndSession(
    calls: Call[],
    sessionTokenToSign: OffChainSession,
    accountAddress: string,
    outsideExecution: OutsideExecution,
    revision: typedData.TypedDataRevision,
    cacheAuthorization: boolean,
  ): Promise<bigint[]> {
    // TODO backend must verify, timestamps fees, used tokens nfts...
    const currentTypedData = getTypedData(outsideExecution, await provider.getChainId(), revision);
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(sessionTokenToSign), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      messageHash,
      sessionMessageHash,
      +cacheAuthorization,
    ]);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.backendKey.privateKey));
    return [signature.r, signature.s];
  }

  public getBackendKey(accountAddress: string): bigint {
    return this.backendKey.publicKey;
  }
}
