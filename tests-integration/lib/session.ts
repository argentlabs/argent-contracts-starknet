import { typedData, Uint256, BigNumberish } from "starknet";
import { provider } from ".";

export const sessionTypes = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  "Allowed Method": [
    { name: "Contract Address", type: "felt" },
    { name: "selector", type: "selector" },
  ],
  Session: [
    { name: "Expires At", type: "felt" },
    { name: "Allowed Methods", type: "merkletree", contains: "Allowed Method" },
    { name: "Guardian Key", type: "felt" },
    { name: "Session Key", type: "felt" },
  ],
};

export const ALLOWED_METHOD_HASH = typedData.getTypeHash(sessionTypes, "Allowed Method");

export interface StarknetSig {
  r: BigNumberish;
  s: BigNumberish;
}

export interface TokenAmount {
  token_address: string;
  amount: Uint256;
}

export interface AllowedMethod {
  "Contract Address": string;
  selector: string;
}

export interface OffChainSession {
  expires_at: BigNumberish;
  allowed_methods: AllowedMethod[];
  guardian_key: BigNumberish;
  session_key: BigNumberish;
}

interface OnChainSession {
  expires_at: BigNumberish;
  allowed_methods_root: string;
  token_amounts: TokenAmount[];
  nft_contracts: string[];
  max_fee_usage: TokenAmount;
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
      "Guardian Key": sessionRequest.guardian_key,
      "Session Key": sessionRequest.session_key,
    },
  };
}
