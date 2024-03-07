import { Call, CallData, hash, num, RawArgs, SignerInterface, typedData } from "starknet";
import { provider } from "./";

const typesRev0 = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  OutsideExecution: [
    { name: "caller", type: "felt" },
    { name: "nonce", type: "felt" },
    { name: "execute_after", type: "felt" },
    { name: "execute_before", type: "felt" },
    { name: "calls_len", type: "felt" },
    { name: "calls", type: "OutsideCall*" },
  ],
  OutsideCall: [
    { name: "to", type: "felt" },
    { name: "selector", type: "felt" },
    { name: "calldata_len", type: "felt" },
    { name: "calldata", type: "felt*" },
  ],
};

const typesRev1 = {
  StarknetDomain: [
    { name: "name", type: "shortstring" },
    { name: "version", type: "shortstring" },
    { name: "chainId", type: "shortstring" },
    { name: "revision", type: "shortstring" },
  ],
  OutsideExecution: [
    { name: "Caller", type: "ContractAddress" },
    { name: "Nonce", type: "felt" },
    { name: "Execute After", type: "u128" },
    { name: "Execute Before", type: "u128" },
    { name: "Calls", type: "Call*" },
  ],
  Call: [
    { name: "To", type: "ContractAddress" },
    { name: "Selector", type: "selector" },
    { name: "Calldata", type: "felt*" },
  ],
};

function getDomain(chainId: string, revision: typedData.TypedDataRevision) {
  if (revision == typedData.TypedDataRevision.Active) {
    return {
      name: "Account.execute_from_outside",
      version: "1",
      chainId: chainId,
      revision: "1",
    };
  }
  return {
    name: "Account.execute_from_outside",
    version: "1",
    chainId: chainId,
  };
}

export interface OutsideExecution {
  caller: string;
  nonce: num.BigNumberish;
  execute_after: num.BigNumberish;
  execute_before: num.BigNumberish;
  calls: OutsideCall[];
}

export interface OutsideCall {
  to: string;
  selector: num.BigNumberish;
  calldata: RawArgs;
}

export function getOutsideCall(call: Call): OutsideCall {
  return {
    to: call.contractAddress,
    selector: hash.getSelectorFromName(call.entrypoint),
    calldata: call.calldata ?? [],
  };
}

export function getTypedDataHash(
  outsideExecution: OutsideExecution,
  accountAddress: num.BigNumberish,
  chainId: string,
  revision: typedData.TypedDataRevision,
): string {
  return typedData.getMessageHash(getTypedData(outsideExecution, chainId, revision), accountAddress);
}

export function getTypedData(
  outsideExecution: OutsideExecution,
  chainId: string,
  revision: typedData.TypedDataRevision,
) {
  if (revision == typedData.TypedDataRevision.Active) {
    return {
      types: typesRev1,
      primaryType: "OutsideExecution",
      domain: getDomain(chainId, revision),
      message: {
        Caller: outsideExecution.caller,
        Nonce: outsideExecution.nonce,
        "Execute After": outsideExecution.execute_after,
        "Execute Before": outsideExecution.execute_before,
        Calls: outsideExecution.calls.map((call) => {
          return {
            To: call.to,
            Selector: call.selector,
            Calldata: call.calldata,
          };
        }),
      },
    };
  }

  return {
    types: typesRev0,
    primaryType: "OutsideExecution",
    domain: getDomain(chainId, revision),
    message: {
      ...outsideExecution,
      calls_len: outsideExecution.calls.length,
      calls: outsideExecution.calls.map((call) => {
        return {
          ...call,
          calldata_len: call.calldata.length,
          calldata: call.calldata,
        };
      }),
    },
  };
}

export async function getOutsideExecutionCall(
  outsideExecution: OutsideExecution,
  accountAddress: string,
  signer: SignerInterface,
  revision: typedData.TypedDataRevision,
  chainId?: string,
): Promise<Call> {
  chainId = chainId ?? (await provider.getChainId());
  const currentTypedData = getTypedData(outsideExecution, chainId, revision);
  const signature = await signer.signMessage(currentTypedData, accountAddress);
  return {
    contractAddress: accountAddress,
    entrypoint: revision == typedData.TypedDataRevision.Active ? "execute_from_outside_v2" : "execute_from_outside",
    calldata: CallData.compile({ ...outsideExecution, signature }),
  };
}
