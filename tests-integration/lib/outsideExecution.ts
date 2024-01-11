import { Call, CallData, hash, num, RawArgs, SignerInterface, typedData } from "starknet";
import { provider } from "./provider";
import { DappSigner } from "./sessionServices";

const types = {
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

function getDomain(chainId: string) {
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
): string {
  return typedData.getMessageHash(getTypedData(outsideExecution, chainId), accountAddress);
}

export function getTypedData(outsideExecution: OutsideExecution, chainId: string) {
  return {
    types: types,
    primaryType: "OutsideExecution",
    domain: getDomain(chainId),
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
  chainId?: string,
): Promise<Call> {
  chainId = chainId ?? (await provider.getChainId());
  const currentTypedData = getTypedData(outsideExecution, chainId);
  const signature = await signer.signMessage(currentTypedData, accountAddress);
  return {
    contractAddress: accountAddress,
    entrypoint: "execute_from_outside",
    calldata: CallData.compile({ ...outsideExecution, signature }),
  };
}

export async function getOutsideExecutionCallWithSession(
  calls: Call[],
  accountAddress: string,
  signer: DappSigner,
): Promise<Call> {
  // dapp + guardian
  const outsideExecution = signer.getOustideExecutionStruct(calls);
  const signature = await signer.signOutsideTransaction(calls, accountAddress, outsideExecution);

  return {
    contractAddress: accountAddress,
    entrypoint: "execute_from_outside",
    calldata: CallData.compile({ ...outsideExecution, signature }),
  };
}
