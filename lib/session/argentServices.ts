import {
  Account,
  ArraySignatureType,
  Call,
  InvocationsSignerDetails,
  TypedData,
  TypedDataRevision,
  ec,
  hash,
  num,
  typedData,
} from "starknet";
import {
  OffChainSession,
  OutsideExecution,
  StarknetKeyPair,
  calculateTransactionHash,
  getSessionTypedData,
  getTypedData,
  manager,
} from "..";

export class ArgentX {
  constructor(
    public account: Account,
    public backendService: BackendService,
  ) {}

  public async getOffchainSignature(typedData: TypedData): Promise<ArraySignatureType> {
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
    cacheOwnerGuid: bigint,
    isLegacyAccount: boolean,
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

    const transactionHash = calculateTransactionHash(transactionDetail, calls);
    const sessionMessageHash = typedData.getMessageHash(
      await getSessionTypedData(sessionTokenToSign),
      transactionDetail.walletAddress,
    );
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      transactionHash,
      sessionMessageHash,
      isLegacyAccount ? +(cacheOwnerGuid !== 0n) : cacheOwnerGuid,
    ]);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.backendKey.privateKey));
    return [signature.r, signature.s];
  }

  public async signOutsideTxAndSession(
    _calls: Call[],
    sessionTokenToSign: OffChainSession,
    accountAddress: string,
    outsideExecution: OutsideExecution,
    revision: TypedDataRevision,
    cacheOwnerGuid: bigint,
  ): Promise<bigint[]> {
    // TODO backend must verify, timestamps fees, used tokens nfts...
    const currentTypedData = getTypedData(outsideExecution, await manager.getChainId(), revision);
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);
    const sessionMessageHash = typedData.getMessageHash(await getSessionTypedData(sessionTokenToSign), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([messageHash, sessionMessageHash, cacheOwnerGuid]);
    const signature = ec.starkCurve.sign(sessionWithTxHash, num.toHex(this.backendKey.privateKey));
    return [signature.r, signature.s];
  }

  public getBackendKey(_accountAddress: string): bigint {
    return this.backendKey.publicKey;
  }
}
