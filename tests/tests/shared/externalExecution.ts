import { Call, CallData, hash, num, RawArgs, SignerInterface, typedData, WeierstrassSignatureType } from "starknet";
import { provider } from "./constants";

const types = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  ExternalExecution: [
    { name: "sender", type: "felt" },
    { name: "min_timestamp", type: "felt" },
    { name: "max_timestamp", type: "felt" },
    { name: "calls_len", type: "felt" },
    { name: "calls", type: "ExternalCall*" },
  ],
  ExternalCall: [
    { name: "to", type: "felt" },
    { name: "selector", type: "felt" },
    { name: "calldata_len", type: "felt" },
    { name: "calldata", type: "felt*" },
  ],
};

function getDomain(chainId: string) {
  return {
    name: "ArgentAccount.execute_external",
    version: "1",
    chainId: chainId,
  };
}

declare type ExternalExecution = {
  sender: string;
  min_timestamp: num.BigNumberish;
  max_timestamp: num.BigNumberish;
  calls: ExternalCall[];
};

declare type ExternalCall = {
  to: string;
  selector: num.BigNumberish;
  calldata: RawArgs;
};

function getExternalCall(call: Call): ExternalCall {
  return {
    to: call.contractAddress,
    selector: hash.getSelectorFromName(call.entrypoint),
    calldata: call.calldata ?? [],
  };
}

function getTypedDataHash(externalExecution: ExternalExecution, accountAddress: num.BigNumberish, chainId: string) {
  return typedData.getMessageHash(getTypedData(externalExecution, chainId), accountAddress);
}

function getTypedData(externalExecution: ExternalExecution, chainId: string) {
  return {
    types: types,
    primaryType: "ExternalExecution",
    domain: getDomain(chainId),
    message: {
      ...externalExecution,
      calls_len: externalExecution.calls.length,
      calls: externalExecution.calls.map((call) => {
        return {
          ...call,
          calldata_len: call.calldata.length,
          calldata: call.calldata,
        };
      }),
    },
  };
}

async function getExternalExecutionCall(
  externalExecution: ExternalExecution,
  accountAddress: string,
  signer: SignerInterface,
  chainId?: string,
): Promise<Call> {
  chainId = chainId ?? (await provider.getChainId());
  const currentTypedData = getTypedData(externalExecution, chainId);
  const signature = await signer.signMessage(currentTypedData, accountAddress);
  return {
    contractAddress: accountAddress,
    entrypoint: "execute_external",
    calldata: CallData.compile({ ...externalExecution, signature }),
  };
}

export { getExternalExecutionCall, getTypedData, getTypedDataHash, getExternalCall, ExternalExecution };
