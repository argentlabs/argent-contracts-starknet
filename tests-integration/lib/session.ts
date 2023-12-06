import { num, typedData, hash, merkle, Call, uint256, BigNumberish, selector } from "starknet";
import { provider } from ".";

export const sessionTypes = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  "Allowed Method": [
    { name: "contract_address", type: "ContractAddress" },
    { name: "selector", type: "selector" },
  ],
  "TokenAmount": [
    { name: "token_address", type: "ContractAddress" },
    { name: "amount", type: "u256" },
  ],
  u256: [
    { name: "low", type: "felt" },
    { name: "high", type: "felt" },
  ],
  Session: [
    { name: "Expires At", type: "felt" },
    { name: "Allowed Methods", type: "merkletree", contains: "Allowed Method" },
    { name: "Token Amounts", type: "TokenAmount*" },
    { name: "NFT Contracts", type: "felt*" },
    { name: "Max Fee Usage", type: "felt" },
    { name: "Session Key", type: "felt" },
  ],
};

export const ALLOWED_METHOD_HASH = typedData.getTypeHash(sessionTypes, "Allowed Method");

export interface TokenAmount {
  token_address: string;
  amount: uint256.Uint256;
}

export interface AllowedMethod {
  contract_address: string;
  selector: string;
}

export interface OffChainSession {
  expires_at: BigNumberish;
  allowed_methods: AllowedMethod[];
  token_limits: TokenAmount[];
  nft_contracts: string[];
  max_fee_usage: BigNumberish;
  session_key: BigNumberish;
}

export interface OnChainSession {
  expires_at: BigNumberish;
  allowed_methods_root: string;
  token_limits: TokenAmount[];
  nft_contracts: string[];
  max_fee_usage: num.BigNumberish;
  session_key: BigNumberish;
}

export interface SessionToken {
  session: OnChainSession;
  session_signature: num.BigNumberish[];
  owner_signature: num.BigNumberish[];
  backend_signature: num.BigNumberish[];
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
      "Token Amounts": sessionRequest.token_limits,
      "NFT Contracts": sessionRequest.nft_contracts,
      "Allowed Methods": sessionRequest.allowed_methods,
      "Max Fee Usage": sessionRequest.max_fee_usage,
      "Session Key": sessionRequest.session_key,
    },
  };
}

export function getLeaves(allowedMethods: AllowedMethod[]): string[] {
  return allowedMethods.map((method) =>
    hash.computeHashOnElements([ALLOWED_METHOD_HASH, method.contract_address, method.selector]),
  );
}

export function createOnChainSession(completedSession: OffChainSession): OnChainSession {
  const leaves = getLeaves(completedSession.allowed_methods);
  return {
    expires_at: completedSession.expires_at,
    allowed_methods_root: new merkle.MerkleTree(leaves).root.toString(),
    token_limits: completedSession.token_limits,
    nft_contracts: completedSession.nft_contracts,
    max_fee_usage: completedSession.max_fee_usage,
    session_key: completedSession.session_key,
  };
}

export function getSessionProofs(calls: Call[], allowedMethods: AllowedMethod[]): string[][] {
  const tree = new merkle.MerkleTree(getLeaves(allowedMethods));

  return calls.map((call) => {
    const allowedIndex = allowedMethods.findIndex((allowedMethod) => {
      return (
        allowedMethod.contract_address == call.contractAddress &&
        allowedMethod.selector == selector.getSelectorFromName(call.entrypoint)
      );
    });
    return tree.getProof(tree.leaves[allowedIndex]);
  });
}
