import { assert, expect } from "chai";
import {
  DeployContractUDCResponse,
  InvokeFunctionResponse,
  GetTransactionReceiptResponse,
  hash,
  num,
  shortString,
  RPC,
} from "starknet";
import { isEqual } from "lodash-es";
import { provider } from "./provider";
import { ensureAccepted } from "./receipts";

export async function expectRevertWithErrorMessage(
  errorMessage: string,
  execute: () => Promise<DeployContractUDCResponse | InvokeFunctionResponse | GetTransactionReceiptResponse>,
) {
  try {
    const executionResult = await execute();
    if (!("transaction_hash" in executionResult)) {
      throw Error(`No transaction hash found on ${JSON.stringify(executionResult)}`);
    }
    await provider.waitForTransaction(executionResult["transaction_hash"]);
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

async function expectEventFromReceipt(receipt: GetTransactionReceiptResponse, event: RPC.Event) {
  receipt = ensureAccepted(receipt);
  expect(event.keys.length).to.be.greaterThan(0, "Unsupported: No keys");
  const events = receipt.events ?? [];
  const normalizedEvent = normalizeEvent(event);
  const matches = events.filter((e) => isEqual(normalizeEvent(e), normalizedEvent)).length;
  console.log("events");
  console.log(events);
  console.log("event");
  console.log(event);
  if (matches == 0) {
    assert(false, "No matches detected in this transaction`");
  } else if (matches > 1) {
    assert(false, "Multiple matches detected in this transaction`");
  }
}

function normalizeEvent(event: RPC.Event): RPC.Event {
  return {
    from_address: event.from_address.toLowerCase(),
    keys: event.keys.map(num.toBigInt).map((key) => key.toString()),
    data: event.data.map(num.toBigInt).map((data) => data.toString()),
  };
}

function convertToEvent(eventWithName: EventWithName): RPC.Event {
  const selector = hash.getSelectorFromName(eventWithName.eventName);
  return {
    from_address: eventWithName.from_address,
    keys: [selector].concat(eventWithName.additionalKeys ?? []),
    data: eventWithName.data ?? [],
  };
}

export async function expectEvent(
  param: string | GetTransactionReceiptResponse | (() => Promise<InvokeFunctionResponse>),
  event: RPC.Event | EventWithName,
) {
  if (typeof param === "function") {
    ({ transaction_hash: param } = await param());
  }
  if (typeof param === "string") {
    param = await provider.waitForTransaction(param);
  }
  if ("eventName" in event) {
    event = convertToEvent(event);
  }
  await expectEventFromReceipt(param, event);
}

export async function waitForTransaction({
  transaction_hash,
}: InvokeFunctionResponse): Promise<GetTransactionReceiptResponse> {
  return await provider.waitForTransaction(transaction_hash);
}

export interface EventWithName {
  from_address: string;
  eventName: string;
  additionalKeys?: Array<string>;
  data?: Array<string>;
}
