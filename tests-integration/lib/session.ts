import { typedData, BigNumberish } from "starknet";
import { provider } from ".";

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
    { name: "Guardian Key", type: "felt" },
    { name: "Session Key", type: "felt" },
  ],
};

export const ALLOWED_METHOD_HASH = typedData.getTypeHash(
  sessionTypes,
  "Allowed Method",
  typedData.TypedDataRevision.Active,
);

export interface StarknetSig {
  r: BigNumberish;
  s: BigNumberish;
}

export interface AllowedMethod {
  "Contract Address": string;
  selector: string;
}

export interface OffChainSession {
  expires_at: BigNumberish;
  allowed_methods: AllowedMethod[];
  metadata: string;
  guardian_key: BigNumberish;
  session_key: BigNumberish;
}

interface OnChainSession {
  expires_at: BigNumberish;
  allowed_methods_root: string;
  metadata_hash: string;
  guardian_key: BigNumberish;
  session_key: BigNumberish;
}

export interface SessionToken {
  session: OnChainSession;
  account_signature: string[];
  session_signature: StarknetSig;
  backend_signature: StarknetSig;
  proofs: string[][];
}

export async function getSessionDomain(): Promise<typedData.StarkNetDomain> {
  const chainId = await provider.getChainId();
  return {
    name: "SessionAccount.session",
    version: "1",
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
      "Guardian Key": sessionRequest.guardian_key,
      "Session Key": sessionRequest.session_key,
    },
  };
}
