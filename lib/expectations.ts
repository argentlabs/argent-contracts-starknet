import { assert, expect } from "chai";
import {
  DeployContractUDCResponse,
  GetTransactionReceiptResponse,
  InvokeFunctionResponse,
  shortString,
} from "starknet";
import { manager } from "./manager";

export async function expectRevertWithErrorMessage(
  errorMessage: string,
  execute: () => Promise<DeployContractUDCResponse | InvokeFunctionResponse | GetTransactionReceiptResponse>,
) {
  try {
    const executionResult = await execute();
    if (!("transaction_hash" in executionResult)) {
      throw new Error(`No transaction hash found on ${JSON.stringify(executionResult)}`);
    }
    await manager.waitForTx(executionResult["transaction_hash"]);
  } catch (e: any) {
    if (!e.toString().includes(shortString.encodeShortString(errorMessage))) {
      const match = e.toString().match(/\[([^\]]+)]/);
      if (match && match.length > 1) {
        console.log(e);
        assert.fail(`"${errorMessage}" not detected, instead got: "${shortString.decodeShortString(match[1])}"`);
      } else {
        assert.fail(`No error detected in: ${e.toString()}`);
      }
    }
    return;
  }
  assert.fail("No error detected");
}

export async function expectExecutionRevert(errorMessage: string, execute: () => Promise<InvokeFunctionResponse>) {
  try {
    await manager.waitForTx(await execute());
    /* eslint-disable  @typescript-eslint/no-explicit-any */
  } catch (e: any) {
    expect(e.toString()).to.contain(`Failure reason: ${shortString.encodeShortString(errorMessage)}`);
    return;
  }
  assert.fail("No error detected");
}
