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
    await waitForTransaction(await execute());
    /* eslint-disable  @typescript-eslint/no-explicit-any */
  } catch (e: any) {
    expect(e.toString()).to.contain(shortString.encodeShortString(errorMessage));
    return;
  }
  assert.fail("No error detected");
}

async function expectEventFromReceipt(receipt: InvokeTransactionReceiptResponse, event: Event) {
  if (!receipt.events) {
    assert.fail("No events triggered");
  }
  expect(event.keys.length).to.equal(1, "Unsupported: Multiple keys");
  const selector = hash.getSelectorFromName(event.keys[0]);
  const eventFiltered = receipt.events.filter((e) => e.keys[0] == selector);
  expect(eventFiltered.length != 0, `No event detected in this transaction: ${receipt.transaction_hash}`).to.be.true;
  expect(eventFiltered.length).to.equal(1, "Unsupported: Multiple events with same selector detected");
  const currentEvent = eventFiltered[0];
  expect(currentEvent.from_address).to.deep.equal(event.from_address);
  // Needs deep equality for array, can't do to.equal
  const currentEventData = currentEvent.data.map(num.toBigInt);
  const eventData = event.data.map(num.toBigInt);
  expect(currentEventData).to.deep.equal(eventData);
}

export async function expectEvent(
  param: string | InvokeTransactionReceiptResponse | (() => Promise<InvokeFunctionResponse>),
  event: Event,
) {
  if (typeof param === "function") {
    ({ transaction_hash: param } = await param());
  }
  if (typeof param === "string") {
    param = await provider.waitForTransaction(param);
  }
  await expectEventFromReceipt(param, event);
}

export async function waitForTransaction({ transaction_hash }: InvokeFunctionResponse) {
  return await provider.waitForTransaction(transaction_hash);
}
