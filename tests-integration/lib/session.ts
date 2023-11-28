import {
    num,
    typedData,
    hash,
    merkle,
    Account,
    WeierstrassSignatureType,
    CallData,
    uint256,
    BigNumberish,
  } from "starknet";
  import { randomKeyPair, ArgentWallet, fundAccount, provider, loadContract } from ".";
  
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
      { name: "backend_key", type: "felt" },
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
  
  export interface IncompleteOffChainSession {
    session_key: BigNumberish;
    expires_at: BigNumberish;
    max_fee_usage: BigNumberish;
    token_limits: TokenLimit[];
    nft_contracts: string[];
    allowed_methods: AllowedMethod[];
  }
  
  export interface CompletedOffChainSession extends IncompleteOffChainSession {
    backend_key: BigNumberish;
  }
  
  export interface OnChainSession {
    session_key: BigNumberish;
    backend_key: BigNumberish;
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
  }
  
  export function getSessionDomain(chainId: string): typedData.StarkNetDomain {
    return {
      name: "SessionAccount.session",
      version: "1",
      chainId: chainId,
    };
  }
  
  export function getSessionTypedData(sessionRequest: CompletedOffChainSession, chainId: string): typedData.TypedData {
    return {
      types: sessionTypes,
      primaryType: "Session",
      domain: getSessionDomain(chainId),
      message: {
        session_key: sessionRequest.session_key,
        backend_key: sessionRequest.backend_key,
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
  
  export function getAllowedMethodRoot(completedSession: CompletedOffChainSession): OnChainSession {
    const allowedMethods = completedSession.allowed_methods ?? [];
    const leaves = getLeaves(allowedMethods);
  
    if (!completedSession.backend_key) {
      throw new Error("Backend key is missing");
    }
    return {
      session_key: completedSession.session_key,
      backend_key: completedSession.backend_key,
      expires_at: completedSession.expires_at,
      allowed_methods_root: new merkle.MerkleTree(leaves).root.toString(),
      max_fee_usage: completedSession.max_fee_usage,
      token_limits: completedSession.token_limits,
      nft_contracts: completedSession.nft_contracts,
    };
  }
  
  export async function getOwnerSessionSignature(
    sessionRequest: CompletedOffChainSession,
    account: Account,
  ): Promise<bigint[]> {
    const sessionTypedData = getSessionTypedData(sessionRequest, await provider.getChainId());
    const { r, s } = (await account.signMessage(sessionTypedData)) as WeierstrassSignatureType;
    return [r, s];
  }
  
  export async function deploySessionAccount(
    argentAccountClassHash: string,
    salt = num.toHex(randomKeyPair().privateKey),
    owner = randomKeyPair(),
  ): Promise<ArgentWallet> {
    const constructorCalldata = CallData.compile({ owner: owner.publicKey });
  
    const contractAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, constructorCalldata, 0);
    await fundAccount(contractAddress, 1e18);
    const account = new Account(provider, contractAddress, owner, "1");
  
    const { transaction_hash } = await account.deploySelf({
      classHash: argentAccountClassHash,
      constructorCalldata,
      addressSalt: salt,
    });
    await provider.waitForTransaction(transaction_hash);
    const accountContract = await loadContract(account.address);
    accountContract.connect(account);
    return { account, accountContract, owner };
  }
  