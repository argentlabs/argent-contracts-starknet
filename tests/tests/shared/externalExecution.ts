import { Call, CallData, num, SignerInterface, typedData, WeierstrassSignatureType } from "starknet";

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

declare type ExternalExecutionArgs = {
  sender: string;
  min_timestamp: num.BigNumberish;
  max_timestamp: num.BigNumberish;
  calls: Call[];
};

function getExternalExecution(externalExecutionArgs: ExternalExecutionArgs) {
  return {
    ...externalExecutionArgs,
    calls: externalExecutionArgs.calls.map((call) => {
      return {
        to: call.contractAddress,
        selector: call.entrypoint,
        calldata: call.calldata ?? [],
      };
    }),
  };
}

function getTypedDataHash(
  externalExecutionArgs: ExternalExecutionArgs,
  accountAddress: num.BigNumberish,
  chainId: string,
) {
  return typedData.getMessageHash(getTypedData(externalExecutionArgs, chainId), accountAddress);
}

function getTypedData(externalExecutionArgs: ExternalExecutionArgs, chainId: string) {
  return {
    types: types,
    primaryType: "ExternalExecution",
    domain: getDomain(chainId),
    message: {
      ...externalExecutionArgs,
      calls_len: externalExecutionArgs.calls.length,
      calls: externalExecutionArgs.calls.map((call) => {
        return {
          to: call.contractAddress,
          selector: call.entrypoint,
          calldata_len: call.calldata?.length ?? 0,
          calldata: call.calldata ?? [],
        };
      }),
    },
  };
}

async function getExternalExecutionCall(
  externalExecutionArgs: ExternalExecutionArgs,
  accountAddress: string,
  signer: SignerInterface,
  chainId: string,
): Promise<Call> {
  const currentTypedData = getTypedData(externalExecutionArgs, chainId);
  const signature = (await signer.signMessage(currentTypedData, accountAddress)) as WeierstrassSignatureType;
  const signatureArray = CallData.compile([signature.r, signature.s]);
  return {
    contractAddress: accountAddress,
    entrypoint: "execute_external",
    calldata: CallData.compile({ ...getExternalExecution(externalExecutionArgs), signatureArray }),
  };
}

export { getExternalExecutionCall, getTypedData, getTypedDataHash, getExternalExecution, ExternalExecutionArgs };
