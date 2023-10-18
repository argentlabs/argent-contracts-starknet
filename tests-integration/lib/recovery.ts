import { hash, ProviderInterface } from "starknet";
import { KeyPair } from ".";

export const signChangeOwnerMessage = async (
  accountAddress: string,
  owner: bigint,
  newOwner: KeyPair,
  provider: ProviderInterface,
) => {
  const messageHash = await getChangeOwnerMessageHash(accountAddress, owner, provider);
  return newOwner.signHash(messageHash);
};

export const getChangeOwnerMessageHash = async (accountAddress: string, owner: bigint, provider: ProviderInterface) => {
  const changeOwnerSelector = hash.getSelectorFromName("change_owner");
  const chainId = await provider.getChainId();
  return hash.computeHashOnElements([changeOwnerSelector, chainId, accountAddress, owner]);
};
