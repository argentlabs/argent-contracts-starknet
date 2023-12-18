import { typedData, uint256, BigNumberish } from "starknet";
import { provider } from ".";

export const sessionTypes = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  "Allowed Method": [
    { name: "Contract Address", type: "ContractAddress" },
    { name: "selector", type: "selector" },
  ],
  TokenAmount: [
    { name: "token_address", type: "ContractAddress" },
    { name: "amount", type: "u256" },
  ],
  u256: [
    { name: "low", type: "u128" },
    { name: "high", type: "u128" },
  ],
  Session: [
    { name: "Expires At", type: "u128" },
    { name: "Allowed Methods", type: "merkletree", contains: "Allowed Method" },
    { name: "Token Amounts", type: "TokenAmount*" },
    { name: "NFT Contracts", type: "felt*" },
    { name: "Max Fee Usage", type: "TokenAmount" },
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
  amount: uint256.Uint256;
}

export interface AllowedMethod {
  "Contract Address": string;
  selector: string;
}

export interface OffChainSession {
  expires_at: BigNumberish;
  allowed_methods: AllowedMethod[];
  token_amounts: TokenAmount[];
  nft_contracts: string[];
  max_fee_usage: TokenAmount;
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
  session_signature: StarknetSig;
  owner_signature: StarknetSig;
  backend_signature: StarknetSig;
  backend_initialization_sig: StarknetSig;
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
      "Token Amounts": sessionRequest.token_amounts,
      "NFT Contracts": sessionRequest.nft_contracts,
      "Max Fee Usage": sessionRequest.max_fee_usage,
      "Guardian Key": sessionRequest.guardian_key,
      "Session Key": sessionRequest.session_key,
    },
  };
}
