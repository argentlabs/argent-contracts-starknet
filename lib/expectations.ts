import { assert, expect } from "chai";
import { InvokeFunctionResponse, shortString } from "starknet";
import { manager } from "./manager";

export async function expectRevertWithErrorMessage(
  errorMessage: string,
  execute: Promise<{ transaction_hash: string }>,
) {
  try {
    await manager.waitForTx(execute);
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

export async function expectExecutionRevert(errorMessage: string, execute: Promise<InvokeFunctionResponse>) {
  try {
    await manager.waitForTx(execute);
    /* eslint-disable  @typescript-eslint/no-explicit-any */
  } catch (e: any) {
    console.log(e);
    expect(e.toString()).to.contain(`Failure reason: ${shortString.encodeShortString(errorMessage)}`);
    return;
  }
  assert.fail("No error detected");
}
