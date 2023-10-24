import { hash, ProviderInterface } from "starknet";
import { KeyPair } from ".";

export const signChangeOwnerMessage = async (
  accountAddress: string,
  owner: bigint,
  newOwner: KeyPair,
  chainId: string,
) => {
  const messageHash = await getChangeOwnerMessageHash(accountAddress, owner, chainId);
  return newOwner.signHash(messageHash);
};

export const getChangeOwnerMessageHash = async (accountAddress: string, owner: bigint, chainId: string) => {
  const changeOwnerSelector = hash.getSelectorFromName("change_owner");
  return hash.computeHashOnElements([changeOwnerSelector, chainId, accountAddress, owner]);
};
