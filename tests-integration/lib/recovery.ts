import { expect } from "chai";
import { Contract, hash, ProviderInterface } from "starknet";
import { KeyPair } from ".";

export enum EscapeStatus {
  None,
  NotReady,
  Ready,
  Expired,
}

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

export async function hasOngoingEscape(accountContract: Contract): Promise<boolean> {
  const escape = await accountContract.get_escape();
  return escape.escape_type != 0n && escape.ready_at != 0n && escape.new_signer != 0n;
}

export async function getEscapeStatus(accountContract: Contract): Promise<EscapeStatus> {
  // StarknetJs parsing is broken so we do it manually
  const result = (await accountContract.call("get_escape_and_status", undefined, { parseResponse: false })) as string[];
  expect(result.length).to.equal(4);
  const status = Number(result[3]);
  expect(status).to.be.lessThan(4, `Unknown status ${status}`);
  return status;
}
