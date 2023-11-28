import { num, typedData, hash, merkle, Account, CallData, Call, uint256, BigNumberish, selector } from "starknet";
import { randomKeyPair, ArgentWalletWithGuardian, fundAccount, provider, loadContract } from ".";

export const sessionTypes = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  AllowedMethod: [
    { name: "contract_address", type: "felt" },
    { name: "selector", type: "selector" },
  ],
  TokenLimit: [
    { name: "contract_address", type: "felt" },
    { name: "amount", type: "u256" },
  ],
  u256: [
    { name: "low", type: "felt" },
    { name: "high", type: "felt" },
  ],
  Session: [
    { name: "session_key", type: "felt" },
    { name: "expires_at", type: "felt" },
    { name: "allowed_methods_root", type: "merkletree", contains: "AllowedMethod" },
    { name: "max_fee_usage", type: "felt" },
    { name: "token_limits", type: "TokenLimit*" },
    { name: "nft_contracts", type: "felt*" },
  ],
};

export const ALLOWED_METHOD_HASH = typedData.getTypeHash(sessionTypes, "AllowedMethod");

export interface TokenLimit {
  contract_address: string;
  amount: uint256.Uint256;
}

export interface AllowedMethod {
  contract_address: string;
  selector: string;
}

export interface OffChainSession {
  session_key: BigNumberish;
  expires_at: BigNumberish;
  max_fee_usage: BigNumberish;
  token_limits: TokenLimit[];
  nft_contracts: string[];
  allowed_methods: AllowedMethod[];
}

export interface OnChainSession {
  session_key: BigNumberish;
  expires_at: BigNumberish;
  max_fee_usage: num.BigNumberish;
  token_limits: TokenLimit[];
  nft_contracts: string[];
  allowed_methods_root: string;
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
      session_key: sessionRequest.session_key,
      expires_at: sessionRequest.expires_at,
      max_fee_usage: sessionRequest.max_fee_usage,
      token_limits: sessionRequest.token_limits,
      nft_contracts: sessionRequest.nft_contracts,
      allowed_methods_root: sessionRequest.allowed_methods,
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
    session_key: completedSession.session_key,
    expires_at: completedSession.expires_at,
    allowed_methods_root: new merkle.MerkleTree(leaves).root.toString(),
    max_fee_usage: completedSession.max_fee_usage,
    token_limits: completedSession.token_limits,
    nft_contracts: completedSession.nft_contracts,
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

export async function deploySessionAccount(
  argentAccountClassHash: string,
  salt = num.toHex(randomKeyPair().privateKey),
  owner = randomKeyPair(),
  guardian = randomKeyPair(),
): Promise<ArgentWalletWithGuardian> {
  const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey });

  const contractAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15); // 0.001 ETH
  const account = new Account(provider, contractAddress, owner, "1");

  const { transaction_hash } = await account.deploySelf({
    classHash: argentAccountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian };
}
