import { expect } from "chai";
import { CairoCustomEnum, Contract, hash } from "starknet";
import { KeyPair, RawSigner } from ".";

export const ESCAPE_SECURITY_PERIOD = 7n * 24n * 60n * 60n; // 7 days
export const ESCAPE_EXPIRY_PERIOD = 2n * 7n * 24n * 60n * 60n; // 14 days
export const MAX_U64 = 2n ** 64n - 1n;

export enum EscapeStatus {
  None,
  NotReady,
  Ready,
  Expired,
}

export const ESCAPE_TYPE_NONE = new CairoCustomEnum({
  None: {},
  Guardian: undefined,
  Owner: undefined,
});

export const ESCAPE_TYPE_GUARDIAN = new CairoCustomEnum({
  None: undefined,
  Guardian: {},
  Owner: undefined,
});

export const ESCAPE_TYPE_OWNER = new CairoCustomEnum({
  None: undefined,
  Guardian: undefined,
  Owner: {},
});

export const signChangeOwnerMessage = async (
  accountAddress: string,
  owner: bigint,
  newOwner: RawSigner,
  chainId: string,
) => {
  const messageHash = await getChangeOwnerMessageHash(accountAddress, owner, chainId);
  return newOwner.signRaw(messageHash);
};

export const getChangeOwnerMessageHash = async (accountAddress: string, owner: bigint, chainId: string) => {
  const changeOwnerSelector = hash.getSelectorFromName("change_owner");
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
