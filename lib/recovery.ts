import { expect } from "chai";
import { CairoCustomEnum, Contract, hash, StarknetDomain, TypedData, typedData, TypedDataRevision } from "starknet";
import { KeyPair } from ".";

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
  newOwner: KeyPair,
  chainId: string,
  maxTimestamp: number,
) => {
  const ReplaceOwnersWithOne: ReplaceOwnersWithOne = {
    new_owner_guid: newOwner.guid.toString(),
    signature_expiration: maxTimestamp.toString(),
  };

  const messageHash = getTypedDataHash(ReplaceOwnersWithOne, chainId, BigInt(accountAddress));
  // const messageHash = await getChangeOwnerMessageHash(accountAddress, chainId, newOwner.guid, maxTimestamp);
  return newOwner.signRaw(messageHash);
};

const types = {
  StarknetDomain: [
    { name: "name", type: "shortstring" },
    { name: "version", type: "shortstring" },
    { name: "chainId", type: "shortstring" },
    { name: "revision", type: "shortstring" },
  ],
  ReplaceOwnersWithOne: [
    { name: "new_owner_guid", type: "felt" },
    { name: "signature_expiration", type: "u128" },
  ],
};

interface ReplaceOwnersWithOne {
  new_owner_guid: string;
  signature_expiration: string;
}

function getDomain(chainId: string): StarknetDomain {
  return {
    name: "replace_all_owners_with_one",
    version: "1",
    chainId,
    revision: TypedDataRevision.ACTIVE,
  };
}

function getTypedDataHash(myStruct: ReplaceOwnersWithOne, chainId: string, owner: bigint): string {
  return typedData.getMessageHash(getTypedData(myStruct, chainId), owner);
}

// Needed to reproduce the same structure as:
// https://github.com/0xs34n/starknet.js/blob/1a63522ef71eed2ff70f82a886e503adc32d4df9/__mocks__/typedDataStructArrayExample.json
function getTypedData(myStruct: ReplaceOwnersWithOne, chainId: string): TypedData {
  return {
    types,
    primaryType: "ReplaceOwnersWithOne",
    domain: getDomain(chainId),
    message: { ...myStruct },
  };
}

export const getChangeOwnerMessageHash = async (
  accountAddress: string,
  chainId: string,
  newOwnerGuid: bigint,
  maxTimestamp: number,
) => {
  const changeOwnerSelector = hash.getSelectorFromName("replace_all_owners_with_one");
  return hash.computeHashOnElements([changeOwnerSelector, chainId, accountAddress, newOwnerGuid, maxTimestamp]);
};

export async function hasOngoingEscape(accountContract: Contract): Promise<boolean> {
  const escape = await accountContract.get_escape();
  return escape.escape_type != 0n && escape.ready_at != 0n && escape.new_signer != 0n;
}

export async function getEscapeStatus(accountContract: Contract): Promise<EscapeStatus> {
  // StarknetJs parsing is broken so we do it manually
  const result = (await accountContract.call("get_escape_and_status", undefined, { parseResponse: false })) as string[];
  const result_len = result.length;
  expect(result_len).to.be.oneOf([4, 6]);
  const status = Number(result[result_len - 1]);
  expect(status).to.be.lessThan(4, `Unknown status ${status}`);
  return status;
}
