import { assert, expect } from "chai";
import { isEqual } from "lodash-es";
import {
  DeployContractUDCResponse,
  GetTransactionReceiptResponse,
  InvokeFunctionResponse,
  SuccessfulTransactionReceiptResponse,
  TransactionReceipt,
  hash,
  num,
  shortString,
} from "starknet";
import { manager } from "./manager";
import { ensureSuccess } from "./receipts";

export async function expectRevertWithErrorMessage(
  errorMessage: string,
  execute: () => Promise<DeployContractUDCResponse | InvokeFunctionResponse | GetTransactionReceiptResponse>,
) {
  try {
    const executionResult = await execute();
    if (!("transaction_hash" in executionResult)) {
      throw new Error(`No transaction hash found on ${JSON.stringify(executionResult)}`);
    }
    await manager.waitForTransaction(executionResult["transaction_hash"]);
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
    await waitForTransaction(await execute());
    /* eslint-disable  @typescript-eslint/no-explicit-any */
  } catch (e: any) {
    expect(e.toString()).to.contain(`Failure reason: ${shortString.encodeShortString(errorMessage)}`);
    return;
  }
  assert.fail("No error detected");
}

async function expectEventFromReceipt(receipt: TransactionReceipt, event: any, eventName?: string) {
  receipt = await ensureSuccess(receipt);
  expect(event.keys.length).to.be.greaterThan(0, "Unsupported: No keys");
  const events = receipt.events ?? [];
  const normalizedEvent = normalizeEvent(event);
  const matches = events.filter((e) => isEqual(normalizeEvent(e), normalizedEvent)).length;
  if (matches == 0) {
    assert.fail(`No matches detected in this transaction: ${eventName}`);
  } else if (matches > 1) {
    assert.fail(`Multiple matches detected in this transaction: ${eventName}`);
  }
}

function normalizeEvent(event: any) {
  return {
    from_address: event.from_address.toLowerCase(),
    keys: event.keys.map(num.toBigInt).map(String),
    data: event.data.map(num.toBigInt).map(String),
  };
}

function convertToEvent(eventWithName: EventWithName) {
  const selector = hash.getSelectorFromName(eventWithName.eventName);
  return {
    from_address: eventWithName.from_address,
    keys: [selector].concat(eventWithName.keys ?? []),
    data: eventWithName.data ?? [],
  };
}

export async function expectEvent(
  param:
    | string
    | GetTransactionReceiptResponse
    | SuccessfulTransactionReceiptResponse
    | (() => Promise<InvokeFunctionResponse>),
  event: EventWithName,
) {
  if (typeof param === "function") {
    ({ transaction_hash: param } = await param());
  }
  if (typeof param === "string") {
    param = await manager.waitForTransaction(param);
  }
  const eventName = event.eventName;
  const convertedEvent = convertToEvent(event);
  await expectEventFromReceipt(param as TransactionReceipt, convertedEvent, eventName);
}

export async function waitForTransaction({
  transaction_hash,
}: InvokeFunctionResponse): Promise<GetTransactionReceiptResponse> {
  return await manager.waitForTransaction(transaction_hash);
}

export interface EventWithName {
  from_address: string;
  eventName: string;
  keys?: Array<string>;
  data?: Array<string>;
}
