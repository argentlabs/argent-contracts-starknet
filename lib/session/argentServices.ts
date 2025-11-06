import {
  Account,
  ArraySignatureType,
  Call,
  InvocationsSignerDetails,
  TypedData,
  TypedDataRevision,
  typedData,
} from "starknet";
import {
  EstimateStarknetKeyPair,
  OutsideExecution,
  Session,
  StarknetKeyPair,
  calculateTransactionHash,
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
  constructor(private backendKey: StarknetKeyPair | EstimateStarknetKeyPair) {}

  public async signTxAndSession(
    calls: Call[],
    transactionDetail: InvocationsSignerDetails,
    sessionTokenToSign: Session,
    cacheOwnerGuid?: bigint,
  ): Promise<bigint[]> {
    // verify session param correct
    // extremely simplified version of the backend verification
    // backend must check, timestamps fees, used tokens nfts...
    const allowedMethods = sessionTokenToSign.allowedMethods;
    if (
      !calls.every((call) => {
        return allowedMethods.some(
          (method) => method["Contract Address"] === call.contractAddress && method.selector === call.entrypoint,
        );
      })
    ) {
      throw new Error("Call not allowed by backend");
    }

    const transactionHash = calculateTransactionHash(transactionDetail, calls);
    const sessionWithTxHash = await sessionTokenToSign.hashWithTransaction(
      transactionHash,
      transactionDetail.walletAddress,
      cacheOwnerGuid,
    );
    const signature = await this.backendKey.signRaw(sessionWithTxHash);
    return [BigInt(signature[2]), BigInt(signature[3])];
  }

  public async signOutsideTxAndSession(
    _calls: Call[],
    sessionTokenToSign: Session,
    accountAddress: string,
    outsideExecution: OutsideExecution,
    revision: TypedDataRevision,
    cacheOwnerGuid?: bigint,
  ): Promise<bigint[]> {
    // TODO backend must verify, timestamps fees, used tokens nfts...
    const currentTypedData = getTypedData(outsideExecution, await manager.getChainId(), revision);
    const messageHash = typedData.getMessageHash(currentTypedData, accountAddress);
    const sessionWithTxHash = await sessionTokenToSign.hashWithTransaction(messageHash, accountAddress, cacheOwnerGuid);
    const signature = await this.backendKey.signRaw(sessionWithTxHash);
    return [BigInt(signature[2]), BigInt(signature[3])];
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  public getBackendKey(_accountAddress: string): bigint {
    return this.backendKey.publicKey;
  }
}
