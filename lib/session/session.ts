import {
  ArraySignatureType,
  BigNumberish,
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
export interface OffChainSession {
  expires_at: BigNumberish;
  allowed_methods: AllowedMethod[];
  metadata: string;
  session_key_guid: BigNumberish;
}

export interface OnChainSession {
  expires_at: BigNumberish;
  allowed_methods_root: string;
  metadata_hash: string;
  session_key_guid: BigNumberish;
}

export interface SessionToken {
  session: OnChainSession;
  cache_owner_guid: BigNumberish;
  session_authorization: string[];
  session_signature: CairoCustomEnum;
  guardian_signature: CairoCustomEnum;
  proofs: string[][];
}

export class SessionToken {
  public session: OnChainSession;
  public proofs: string[][];
  private legacyMode: boolean;

  constructor(args: {
    session: Session;
    cache_owner_guid: BigNumberish;
    session_authorization: string[];
    session_signature: CairoCustomEnum;
    guardian_signature: CairoCustomEnum;
    calls: Call[];
    isLegacyAccount: boolean;
  }) {
    const {
      session,
      cache_owner_guid,
      session_authorization,
      session_signature,
      guardian_signature,
      calls,
      isLegacyAccount,
    } = args;

    this.session = session.toOnChainSession();
    this.proofs = session.getProofs(calls);
    this.cache_owner_guid = cache_owner_guid;
    this.session_authorization = session_authorization;
    this.session_signature = session_signature;
    this.guardian_signature = guardian_signature;
    this.legacyMode = isLegacyAccount;
  }

  public compileSignature(): string[] {
    const SESSION_MAGIC = shortString.encodeShortString("session-token");
    const tokenData = {
      session: this.session,
      ...(this.legacyMode
        ? { cache_authorization: this.cache_owner_guid !== 0n }
        : { cache_owner_guid: this.cache_owner_guid }),
      session_authorization: this.session_authorization,
      session_signature: this.session_signature,
      guardian_signature: this.guardian_signature,
      proofs: this.proofs,
    };
    return [SESSION_MAGIC, ...CallData.compile(tokenData)];
  }
}

export class Session {
  public offChainSession: OffChainSession;
  private merkleTree: merkle.MerkleTree;
  private legacyMode: boolean;

  constructor(
    public expires_at: BigNumberish,
    public allowed_methods: AllowedMethod[],
    public metadata: string,
    public session_key_guid: BigNumberish,
    isLegacyAccount = false,
  ) {
    this.offChainSession = {
      expires_at,
      allowed_methods,
      metadata,
      session_key_guid,
    };
    this.merkleTree = this.buildMerkleTree();
    this.legacyMode = isLegacyAccount;
  }

  private buildMerkleTree(): merkle.MerkleTree {
    const leaves = this.allowed_methods.map((method) =>
      hash.computePoseidonHashOnElements([
        ALLOWED_METHOD_HASH,
        method["Contract Address"],
        selector.getSelectorFromName(method.selector),
      ]),
    );
    return new merkle.MerkleTree(leaves, hash.computePoseidonHash);
  }

  public getProofs(calls: Call[]): string[][] {
    return calls.map((call) => {
      const allowedIndex = this.allowed_methods.findIndex((allowedMethod) => {
        return allowedMethod["Contract Address"] == call.contractAddress && allowedMethod.selector == call.entrypoint;
      });
      return this.merkleTree.getProof(this.merkleTree.leaves[allowedIndex], this.merkleTree.leaves);
    });
  }

  public async isSessionCached(accountAddress: string, cache_owner_guid: bigint): Promise<boolean> {
    const sessionContract = await manager.loadContract(accountAddress);
    const sessionMessageHash = typedData.getMessageHash(await this.getTypedData(), accountAddress);
    const isSessionCached = this.legacyMode
      ? await sessionContract.is_session_authorization_cached(sessionMessageHash)
      : await sessionContract.is_session_authorization_cached(sessionMessageHash, cache_owner_guid);
    return isSessionCached;
  }

  public async hashWithTransaction(
    transactionHash: string,
    accountAddress: string,
    cacheOwnerGuid: bigint,
  ): Promise<string> {
    const sessionMessageHash = typedData.getMessageHash(await this.getTypedData(), accountAddress);
    const sessionWithTxHash = hash.computePoseidonHashOnElements([
      transactionHash,
      sessionMessageHash,
      this.legacyMode ? +(cacheOwnerGuid !== 0n) : cacheOwnerGuid,
    ]);
    return sessionWithTxHash;
  }

  public async getTypedData(): Promise<TypedData> {
    return {
      types: sessionTypes,
      primaryType: "Session",
      domain: await this.getSessionDomain(),
      message: {
        "Expires At": this.expires_at,
        "Allowed Methods": this.allowed_methods,
        Metadata: this.metadata,
        "Session Key": this.session_key_guid,
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
    const elements = [bArray.data.length, ...bArray.data, bArray.pending_word, bArray.pending_word_len];
    const metadataHash = hash.computePoseidonHashOnElements(elements);

    return {
      expires_at: this.expires_at,
      allowed_methods_root: this.merkleTree.root.toString(),
      metadata_hash: metadataHash,
      session_key_guid: this.session_key_guid,
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
  mockDappContractAddress,
  allowedMethods,
  expiry = BigInt(Date.now()) + 10000n,
  dappKey = randomStarknetKeyPair(),
  cacheOwnerGuid = 0n,
  isLegacyAccount = false,
}: {
  guardian: StarknetKeyPair;
  account: ArgentAccount;
  mockDappContractAddress?: string;
  allowedMethods?: AllowedMethod[];
  expiry?: bigint;
  dappKey?: StarknetKeyPair;
  cacheOwnerGuid?: bigint;
  isLegacyAccount?: boolean;
}): Promise<SessionSetup> {
  const allowedMethodsList =
    allowedMethods ??
    (mockDappContractAddress
      ? [
          {
            "Contract Address": mockDappContractAddress,
            selector: "set_number_double",
          },
        ]
      : []);

  const backendService = new BackendService(guardian);
  const dappService = new DappService(backendService, dappKey);
  const argentX = new ArgentX(account, backendService);
  const sessionRequest = dappService.createSessionRequest(allowedMethodsList, expiry, isLegacyAccount);
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
    allowedMethods: allowedMethodsList,
    sessionRequest,
    authorizationSignature,
    backendService,
    dappService,
    argentX,
  };
}
