import { assert, expect } from "chai";
import { isEqual } from "lodash-es";
import { GetTransactionReceiptResponse, InvokeFunctionResponse, TransactionReceipt, hash, num } from "starknet";
import { ensureSuccess, manager } from ".";

interface Event {
  from_address: string;
  keys?: string[];
  data?: string[];
}

export interface EventWithName extends Event {
  eventName: string;
}

async function expectEventFromReceipt(receipt: TransactionReceipt, event: Event, eventName?: string) {
  receipt = await ensureSuccess(receipt);
  expect(event.keys?.length).to.be.greaterThan(0, "Unsupported: No keys");
  const events = receipt.events ?? [];
  const normalizedEvent = normalizeEvent(event);
  const matches = events.filter((e) => isEqual(normalizeEvent(e), normalizedEvent)).length;
  if (matches == 0) {
    assert.fail(`No matches detected in this transaction: ${eventName}`);
  } else if (matches > 1) {
    assert.fail(`Multiple matches detected in this transaction: ${eventName}`);
  }
}

function normalizeEvent(event: Event): Event {
  return {
    from_address: event.from_address.toLowerCase(),
    keys: event.keys?.map(num.toBigInt).map(String),
    data: event.data?.map(num.toBigInt).map(String),
  };
}

function convertToEvent(eventWithName: EventWithName): Event {
  const selector = hash.getSelectorFromName(eventWithName.eventName);
  return {
    from_address: eventWithName.from_address,
    keys: [selector].concat(eventWithName.keys ?? []),
    data: eventWithName.data ?? [],
  };
}

export async function expectEvent(
  param: string | GetTransactionReceiptResponse | TransactionReceipt | (() => Promise<InvokeFunctionResponse>),
  event: EventWithName,
) {
  if (typeof param === "function") {
    ({ transaction_hash: param } = await param());
  }
  if (typeof param === "string") {
    param = await manager.waitForTx(param);
  }
  const eventName = event.eventName;
  const convertedEvent = convertToEvent(event);
  await expectEventFromReceipt(param as TransactionReceipt, convertedEvent, eventName);
}
