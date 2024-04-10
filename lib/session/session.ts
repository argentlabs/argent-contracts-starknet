import { Account, BigNumberish, CairoCustomEnum, shortString, typedData } from "starknet";
import {
  ArgentAccount,
  ArgentX,
  BackendService,
  DappService,
  StarknetKeyPair,
  provider,
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

export const ALLOWED_METHOD_HASH = typedData.getTypeHash(
  sessionTypes,
  "Allowed Method",
  typedData.TypedDataRevision.Active,
);

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
  session_authorization: string[];
  session_signature: CairoCustomEnum;
  guardian_signature: CairoCustomEnum;
  proofs: string[][];
}

export async function getSessionDomain(): Promise<typedData.StarkNetDomain> {
  // WARNING! Revision is encoded as a number in the StarkNetDomain type and not as shortstring
  // This is due to a bug in the Braavos implementation, and has been kept for compatibility
  const chainId = await provider.getChainId();
  return {
    name: "SessionAccount.session",
    version: shortString.encodeShortString("1"),
    chainId: chainId,
    revision: "1",
  };
}

export async function getSessionTypedData(sessionRequest: OffChainSession): Promise<typedData.TypedData> {
  return {
    types: sessionTypes,
    primaryType: "Session",
    domain: await getSessionDomain(),
    message: {
      "Expires At": sessionRequest.expires_at,
      "Allowed Methods": sessionRequest.allowed_methods,
      Metadata: sessionRequest.metadata,
      "Session Key": sessionRequest.session_key_guid,
    },
  };
}

export async function setupSession(
  guardian: StarknetKeyPair,
  account: Account,
  allowedMethods: AllowedMethod[],
  expiry: bigint = BigInt(Date.now()) + 10000n,
  dappKey: StarknetKeyPair = randomStarknetKeyPair(),
): Promise<ArgentAccount> {
  const backendService = new BackendService(guardian);
  const dappService = new DappService(backendService, dappKey);
  const argentX = new ArgentX(account, backendService);

  const sessionRequest = dappService.createSessionRequest(allowedMethods, expiry);

  const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

  return dappService.getAccountWithSessionSigner(account, sessionRequest, accountSessionSignature);
}
