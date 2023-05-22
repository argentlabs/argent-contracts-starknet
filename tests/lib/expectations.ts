import { assert, expect } from "chai";
import {
  DeployContractUDCResponse,
  Event,
  InvokeFunctionResponse,
  InvokeTransactionReceiptResponse,
  hash,
  num,
  shortString,
} from "starknet";

import { provider } from "./provider";

export async function expectRevertWithErrorMessage(
  errorMessage: string,
  execute: () => Promise<DeployContractUDCResponse | InvokeFunctionResponse>,
) {
  try {
    const { transaction_hash } = await execute();
    await provider.waitForTransaction(transaction_hash);
  } catch (e: any) {
    expect(e.toString()).to.contain(shortString.encodeShortString(errorMessage));
  }
}

export async function expectExecutionRevert(errorMessage: string, execute: () => Promise<InvokeFunctionResponse>) {
  try {
    await execute();
    assert.fail("No error detected");
  } catch (e: any) {
    expect(e.toString()).to.contain(shortString.encodeShortString(errorMessage));
  }
}

async function expectEventFromHash(transactionHash: string, event: Event) {
  const txReceiptDeployTest: InvokeTransactionReceiptResponse = await provider.waitForTransaction(transactionHash);
  if (!txReceiptDeployTest.events) {
    assert.fail("No events triggered");
  }
  expect(event.keys.length).to.equal(1, "Unsupported: Multiple keys");
  const selector = hash.getSelectorFromName(event.keys[0]);
  const eventFiltered = txReceiptDeployTest.events.filter((e) => e.keys[0] == selector);
  expect(eventFiltered.length != 0, `No event detected in this transaction: ${transactionHash}`).to.be.true;
  expect(eventFiltered.length).to.equal(1, "Unsupported: Multiple events with same selector detected");
  const currentEvent = eventFiltered[0];
  expect(currentEvent.from_address).to.deep.equal(event.from_address);
  // Needs deep equality for array, can't do to.equal
  const currentEventData = currentEvent.data.map(num.toBigInt);
  const eventData = event.data.map(num.toBigInt);
  expect(currentEventData).to.deep.equal(eventData);
}

export async function expectEvent(hashOrInvoke: string | (() => Promise<InvokeFunctionResponse>), event: Event) {
  if (typeof hashOrInvoke !== "string") {
    ({ transaction_hash: hashOrInvoke } = await hashOrInvoke());
  }
  await expectEventFromHash(hashOrInvoke, event);
}

export async function waitForTransaction({ transaction_hash: transferTxHash }: InvokeFunctionResponse) {
  return await provider.waitForTransaction(transferTxHash);
}
