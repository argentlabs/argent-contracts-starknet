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
  private legacyMode: boolean;

  constructor(
    public session: OnChainSession,
    public cache_owner_guid: BigNumberish,
    public session_authorization: string[],
    public session_signature: CairoCustomEnum,
    public guardian_signature: CairoCustomEnum,
    public proofs: string[][],
    isLegacyAccount: boolean,
  ) {
    this.legacyMode = isLegacyAccount;
  }

  public static async build(
    session: Session,
    cache_owner_guid: BigNumberish,
    session_authorization: string[],
    session_signature: CairoCustomEnum,
    guardian_signature: CairoCustomEnum,
    calls: Call[],
    isLegacyFormat: boolean,
  ): Promise<SessionToken> {
    const onChainSession = session.toOnChainSession();
    const proofs = session.getProofs(calls);

    return new SessionToken(
      onChainSession,
      cache_owner_guid,
      session_authorization,
      session_signature,
      guardian_signature,
      proofs,
      isLegacyFormat,
    );
  }

  public compileSignature(): string[] {
    const SESSION_MAGIC = shortString.encodeShortString("session-token");
    if (this.legacyMode) {
      return [SESSION_MAGIC, ...CallData.compile(this.toLegacyFormat())];
    } else {
      return [SESSION_MAGIC, ...CallData.compile(this.toCurrentFormat())];
    }
  }

  private toLegacyFormat() {
    return {
      session: this.session,
      cache_authorization: this.cache_owner_guid !== 0n,
      session_authorization: this.session_authorization,
      session_signature: this.session_signature,
      guardian_signature: this.guardian_signature,
      proofs: this.proofs,
    };
  }

  private toCurrentFormat() {
    return {
      session: this.session,
      cache_owner_guid: this.cache_owner_guid,
      session_authorization: this.session_authorization,
      session_signature: this.session_signature,
      guardian_signature: this.guardian_signature,
      proofs: this.proofs,
    };
  }
}

export class Session {
  public offChainSession: OffChainSession;
  private merkleTree: merkle.MerkleTree;

  constructor(
    public expires_at: BigNumberish,
    public allowed_methods: AllowedMethod[],
    public metadata: string,
    public session_key_guid: BigNumberish,
  ) {
    this.offChainSession = {
      expires_at,
      allowed_methods,
      metadata,
      session_key_guid,
    };
    this.merkleTree = this.buildMerkleTree();
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
  sessionRequest: Session;
  authorizationSignature: ArraySignatureType;
  backendService: BackendService;
  dappService: DappService;
  argentX: ArgentX;
}
export async function setupSession(
  guardian: StarknetKeyPair,
  account: ArgentAccount,
  allowedMethods: AllowedMethod[],
  expiry: bigint = BigInt(Date.now()) + 10000n,
  dappKey: StarknetKeyPair = randomStarknetKeyPair(),
  cacheOwnerGuid = 0n,
  isLegacyAccount = false,
): Promise<SessionSetup> {
  const backendService = new BackendService(guardian);
  const dappService = new DappService(backendService, dappKey);
  const argentX = new ArgentX(account, backendService);

  const sessionRequest = dappService.createSessionRequest(allowedMethods, expiry);

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
    sessionRequest,
    authorizationSignature,
    backendService,
    dappService,
    argentX,
  };
}
