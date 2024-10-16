import {
  ArraySignatureType,
  CairoCustomEnum,
  Call,
  CallData,
  StarknetDomain,
  TypedData,
  TypedDataRevision,
  byteArray,
  hash,
  merkle,
  selector,
  shortString,
  typedData,
} from "starknet";
import {
  ArgentAccount,
  ArgentX,
  BackendService,
  DappService,
  StarknetKeyPair,
  manager,
  randomStarknetKeyPair,
} from "..";

export const sessionTypes = {
  StarknetDomain: [
    { name: "name", type: "shortstring" },
    { name: "version", type: "shortstring" },
    { name: "chainId", type: "shortstring" },
    { name: "revision", type: "shortstring" },
  ],
  "Allowed Method": [
    { name: "Contract Address", type: "ContractAddress" },
    { name: "selector", type: "selector" },
  ],
  Session: [
    { name: "Expires At", type: "timestamp" },
    { name: "Allowed Methods", type: "merkletree", contains: "Allowed Method" },
    { name: "Metadata", type: "string" },
    { name: "Session Key", type: "felt" },
  ],
};

export const ALLOWED_METHOD_HASH = typedData.getTypeHash(sessionTypes, "Allowed Method", TypedDataRevision.ACTIVE);

export interface AllowedMethod {
  "Contract Address": string;
  selector: string;
}

export interface OnChainSession {
  expires_at: bigint;
  allowed_methods_root: string;
  metadata_hash: string;
  session_key_guid: bigint;
}

export class SessionToken {
  public session: Session;
  public proofs: string[][];
  public cacheOwnerGuid?: bigint;
  public sessionAuthorization?: string[];
  public sessionSignature: CairoCustomEnum;
  public guardianSignature: CairoCustomEnum;
  private legacyMode: boolean;

  constructor(args: {
    session: Session;
    cacheOwnerGuid?: bigint;
    sessionAuthorization?: string[];
    sessionSignature: CairoCustomEnum;
    guardianSignature: CairoCustomEnum;
    calls: Call[];
    isLegacyAccount: boolean;
  }) {
    const {
      session,
      cacheOwnerGuid,
      sessionAuthorization,
      sessionSignature,
      guardianSignature,
      calls,
      isLegacyAccount,
    } = args;

    this.session = session;
    this.proofs = session.getProofs(calls);
    this.cacheOwnerGuid = cacheOwnerGuid;
    this.sessionAuthorization = sessionAuthorization;
    this.sessionSignature = sessionSignature;
    this.guardianSignature = guardianSignature;
    this.legacyMode = isLegacyAccount;
  }

  public compileSignature(): string[] {
    const SESSION_MAGIC = shortString.encodeShortString("session-token");
    const tokenData = {
      session: this.session.toOnChainSession(),
      ...(this.legacyMode
        ? { cache_authorization: this.cacheOwnerGuid !== undefined }
        : { cache_owner_guid: this.cacheOwnerGuid ?? 0 }),
      session_authorization: this.sessionAuthorization ?? [],
      session_signature: this.sessionSignature,
      guardian_signature: this.guardianSignature,
      proofs: this.proofs,
    };
    return [SESSION_MAGIC, ...CallData.compile(tokenData)];
  }
}

export class Session {
  constructor(
    public expiresAt: bigint,
    public allowedMethods: AllowedMethod[],
    public metadata: string,
    public sessionKeyGuid?: bigint,
    private legacyMode = false,
  ) {}

  private buildMerkleTree(): merkle.MerkleTree {
    const leaves = this.allowedMethods.map((method) =>
      hash.computePoseidonHashOnElements([
        ALLOWED_METHOD_HASH,
        method["Contract Address"],
        selector.getSelectorFromName(method.selector),
      ]),
    );
    return new merkle.MerkleTree(leaves, hash.computePoseidonHash);
  }

  public getProofs(calls: Call[]): string[][] {
    const merkleTree = this.buildMerkleTree();
    return calls.map((call) => {
      const allowedIndex = this.allowedMethods.findIndex((allowedMethod) => {
        return allowedMethod["Contract Address"] == call.contractAddress && allowedMethod.selector == call.entrypoint;
      });
      return merkleTree.getProof(merkleTree.leaves[allowedIndex], merkleTree.leaves);
    });
  }

  public async isSessionCached(accountAddress: string, cacheOwnerGuid?: bigint): Promise<boolean> {
    if (!cacheOwnerGuid) return false;
    const sessionContract = await manager.loadContract(accountAddress);
    const sessionMessageHash = typedData.getMessageHash(await this.getTypedData(), accountAddress);
    const isSessionCached = this.legacyMode
      ? await sessionContract.is_session_authorization_cached(sessionMessageHash)
      : await sessionContract.is_session_authorization_cached(sessionMessageHash, cacheOwnerGuid);
    return isSessionCached;
  }

  public async hashWithTransaction(
    transactionHash: string,
    accountAddress: string,
    cacheOwnerGuid?: bigint,
  ): Promise<string> {
    const sessionMessageHash = typedData.getMessageHash(await this.getTypedData(), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      transactionHash,
      sessionMessageHash,
      this.legacyMode ? +(cacheOwnerGuid != undefined) : cacheOwnerGuid ?? 0,
    ]);
    return sessionWithTxHash;
  }

  public async getTypedData(): Promise<TypedData> {
    return {
      types: sessionTypes,
      primaryType: "Session",
      domain: await this.getSessionDomain(),
      message: {
        "Expires At": this.expiresAt,
        "Allowed Methods": this.allowedMethods,
        Metadata: this.metadata,
        "Session Key": this.sessionKeyGuid,
      },
    };
  }

  private async getSessionDomain(): Promise<StarknetDomain> {
    // WARNING! Revision is encoded as a number in the StarkNetDomain type and not as shortstring
    // This is due to a bug in the Braavos implementation, and has been kept for compatibility
    const chainId = await manager.getChainId();
    return {
      name: "SessionAccount.session",
      version: shortString.encodeShortString("1"),
      chainId: chainId,
      revision: "1",
    };
  }

  public toOnChainSession(): OnChainSession {
    const bArray = byteArray.byteArrayFromString(this.metadata);
    const metadataHash = hash.computePoseidonHashOnElements(CallData.compile(bArray));

    return {
      expires_at: this.expiresAt,
      allowed_methods_root: this.buildMerkleTree().root.toString(),
      metadata_hash: metadataHash,
      session_key_guid: this.sessionKeyGuid ?? 0n,
    };
  }
}

interface SessionSetup {
  accountWithDappSigner: ArgentAccount;
  sessionHash: string;
  allowedMethods: AllowedMethod[];
  sessionRequest: Session;
  authorizationSignature: ArraySignatureType;
  backendService: BackendService;
  dappService: DappService;
  argentX: ArgentX;
}

export async function setupSession({
  guardian,
  account,
  allowedMethods,
  expiry = BigInt(Date.now()) + 10000n,
  dappKey = randomStarknetKeyPair(),
  cacheOwnerGuid = undefined,
  isLegacyAccount = false,
}: {
  guardian: StarknetKeyPair;
  account: ArgentAccount;
  mockDappContractAddress?: string;
  allowedMethods: AllowedMethod[];
  expiry?: bigint;
  dappKey?: StarknetKeyPair;
  cacheOwnerGuid?: bigint;
  isLegacyAccount?: boolean;
}): Promise<SessionSetup> {
  const backendService = new BackendService(guardian);
  const dappService = new DappService(backendService, dappKey);
  const argentX = new ArgentX(account, backendService);
  const sessionRequest = dappService.createSessionRequest(allowedMethods, expiry, isLegacyAccount);
  const sessionTypedData = await sessionRequest.getTypedData();
  const authorizationSignature = await argentX.getOffchainSignature(sessionTypedData);

  return {
    accountWithDappSigner: dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      authorizationSignature,
      cacheOwnerGuid,
      isLegacyAccount,
    ),
    sessionHash: typedData.getMessageHash(sessionTypedData, account.address),
    allowedMethods,
    sessionRequest,
    authorizationSignature,
    backendService,
    dappService,
    argentX,
  };
}
