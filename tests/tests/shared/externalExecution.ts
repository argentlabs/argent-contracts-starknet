import { expect } from "chai";
import {
  Account,
  CairoVersion,
  Call,
  CallData,
  Calldata,
  RawCalldata,
  Signer,
  SignerInterface,
  WeierstrassSignatureType,
  ec,
  hash,
  num,
  stark,
  typedData,
} from "starknet";
import { provider } from "./constants";

const types = {
  StarkNetDomain: [
    { name: "name", type: "felt" },
    { name: "version", type: "felt" },
    { name: "chainId", type: "felt" },
  ],
  ExternalCalls: [
    { name: "sender", type: "felt" },
    { name: "nonce", type: "felt" },
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

declare type ExternalCallsArguments = {
  sender: string;
  nonce: num.BigNumberish;
  min_timestamp: num.BigNumberish;
  max_timestamp: num.BigNumberish;
  calls: Call[];
};

function getExternalCalls(externalCallsArguments: ExternalCallsArguments) {
  return {
    ...externalCallsArguments,
    calls: externalCallsArguments.calls.map((call) => {
      return {
        to: call.contractAddress,
        selector: call.entrypoint,
        calldata: call.calldata ?? [],
      };
    }),
  };
}

function getTypedDataHash(
  externalCallsArguments: ExternalCallsArguments,
  accountAddress: num.BigNumberish,
  chainId: string,
) {
  return typedData.getMessageHash(getTypedData(externalCallsArguments, chainId), accountAddress);
}

function getTypedData(externalCallsArguments: ExternalCallsArguments, chainId: string) {
  return {
    types: types,
    primaryType: "ExternalCalls",
    domain: getDomain(chainId),
    message: {
      ...externalCallsArguments,
      calls_len: externalCallsArguments.calls.length,
      calls: externalCallsArguments.calls.map((call) => {
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

async function getExternalTransactionCall(
  externalCallsArguments: ExternalCallsArguments,
  accountAddress: string,
  signer: SignerInterface,
  chainId: string,
): Promise<Call> {
  const currentTypedData = getTypedData(externalCallsArguments, chainId);
  const signature = (await signer.signMessage(currentTypedData, accountAddress)) as WeierstrassSignatureType;
  const signatureArray = CallData.compile([signature.r, signature.s]);
  return {
    contractAddress: accountAddress,
    entrypoint: "execute_external_calls",
    calldata: CallData.compile({ ...getExternalCalls(externalCallsArguments), signatureArray }),
  };
}

export { getExternalTransactionCall, getTypedData, getTypedDataHash, getExternalCalls, ExternalCallsArguments };
