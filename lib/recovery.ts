import {
  CairoCustomEnum,
  CallData,
  Contract,
  shortString,
  StarknetDomain,
  TypedData,
  typedData,
  TypedDataRevision,
} from "starknet";
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

export const signOwnerAliveMessage = async (
  accountAddress: string,
  newOwner: KeyPair,
  chainId: string,
  maxTimestamp: number,
) => {
  const messageHash = await getOwnerAliveMessageHash(accountAddress, chainId, newOwner.guid, maxTimestamp);
  const signature = await newOwner.signRaw(messageHash);
  return CallData.compile([...signature, maxTimestamp]);
};

const types = {
  StarknetDomain: [
    { name: "name", type: "shortstring" },
    { name: "version", type: "shortstring" },
    { name: "chainId", type: "shortstring" },
    { name: "revision", type: "shortstring" },
  ],
  "Owner Alive": [
    { name: "Owner GUID", type: "felt" },
    { name: "Signature expiration", type: "timestamp" },
  ],
};

interface OwnerAlive {
  ownerGuid: bigint;
  signatureExpiration: number;
}

function getDomain(chainId: string): StarknetDomain {
  return {
    name: "Owner Alive",
    version: shortString.encodeShortString("1"),
    chainId,
    revision: TypedDataRevision.ACTIVE,
  };
}

function getTypedData(myStruct: OwnerAlive, chainId: string): TypedData {
  return {
    types,
    primaryType: "Owner Alive",
    domain: getDomain(chainId),
    message: {
      "Owner GUID": myStruct.ownerGuid,
      "Signature expiration": myStruct.signatureExpiration,
    },
  };
}

export async function getOwnerAliveMessageHash(
  accountAddress: string,
  chainId: string,
  ownerGuid: bigint,
  signatureExpiration: number,
) {
  return typedData.getMessageHash(getTypedData({ ownerGuid, signatureExpiration }, chainId), accountAddress);
}

export async function hasOngoingEscape(accountContract: Contract): Promise<boolean> {
  const escape = await accountContract.get_escape();
  return escape.escape_type != 0n && escape.ready_at != 0n && escape.new_signer != 0n;
}

export async function getEscapeStatus(accountContract: Contract): Promise<EscapeStatus> {
  const result = await accountContract.get_escape_and_status();
  return EscapeStatus[result[1].activeVariant() as keyof typeof EscapeStatus];
}
