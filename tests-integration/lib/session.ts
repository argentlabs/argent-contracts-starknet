import { num, typedData, hash, merkle, Call, uint256, BigNumberish, selector } from "starknet";
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

export interface BasicSignature {
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

export interface OnChainSession {
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
  session_signature: BasicSignature;
  owner_signature: BasicSignature;
  backend_signature: BasicSignature;
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

export function getLeaves(allowedMethods: AllowedMethod[]): string[] {
  return allowedMethods.map((method) =>
    hash.computeHashOnElements([ALLOWED_METHOD_HASH, method["Contract Address"], method.selector]),
  );
}

export function createOnChainSession(completedSession: OffChainSession): OnChainSession {
  const leaves = getLeaves(completedSession.allowed_methods);
  return {
    expires_at: completedSession.expires_at,
    allowed_methods_root: new merkle.MerkleTree(leaves).root.toString(),
    token_amounts: completedSession.token_amounts,
    nft_contracts: completedSession.nft_contracts,
    max_fee_usage: completedSession.max_fee_usage,
    guardian_key: completedSession.guardian_key,
    session_key: completedSession.session_key,
  };
}

export function getSessionProofs(calls: Call[], allowedMethods: AllowedMethod[]): string[][] {
  const tree = new merkle.MerkleTree(getLeaves(allowedMethods));

  return calls.map((call) => {
    const allowedIndex = allowedMethods.findIndex((allowedMethod) => {
      return (
        allowedMethod["Contract Address"] == call.contractAddress &&
        allowedMethod.selector == selector.getSelectorFromName(call.entrypoint)
      );
    });
    return tree.getProof(tree.leaves[allowedIndex], getLeaves(allowedMethods));
  });
}
