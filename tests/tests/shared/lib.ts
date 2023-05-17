import { assert, expect } from "chai";
import { readFileSync } from "fs";
import {
  CompiledSierra,
  CompiledSierraCasm,
  Contract,
  DeclareContractPayload,
  Event,
  InvokeFunctionResponse,
  InvokeTransactionReceiptResponse,
  hash,
  json,
  shortString,
} from "starknet";

import { deployerAccount, provider } from "./constants";

const classHashCache: { [contractName: string]: string } = {};

// Could extends Account to add our specific fn but that's too early.
async function declareContract(contractName: string): Promise<string> {
  console.log(`\tDeclaring ${contractName}...`);
  const cachedClass = classHashCache[contractName];
  if (cachedClass) {
    return cachedClass;
  }
  const contract: CompiledSierra = json.parse(readFileSync(`./contracts/${contractName}.json`).toString("ascii"));
  let returnedClashHash;
  if ("sierra_program" in contract) {
    const casm: CompiledSierraCasm = json.parse(readFileSync(`./contracts/${contractName}.casm`).toString("ascii"));
    returnedClashHash = await actualDeclare({ contract, casm });
  } else {
    returnedClashHash = await actualDeclare({ contract });
  }
  classHashCache[contractName] = returnedClashHash;
  return returnedClashHash;
}

async function actualDeclare(payload: DeclareContractPayload): Promise<string> {
  const { class_hash } = await deployerAccount.declareIfNot(payload, { maxFee: 1e18 }); // max fee avoids slow estimate
  return class_hash;
}

async function loadContract(contract_address: string) {
  const { abi: testAbi } = await provider.getClassAt(contract_address);
  if (!testAbi) {
    throw new Error("Error while getting ABI");
  }
  return new Contract(testAbi, contract_address, provider);
}

async function expectRevertWithErrorMessage(errorMessage: string, fn: () => Promise<void>) {
  try {
    await fn();
    assert.fail("No error detected");
  } catch (e: any) {
    // console.log(e);
    expect(e.toString()).to.contain(shortString.encodeShortString(errorMessage));
  }
}

async function expectEvent(transactionHash: string, event: Event) {
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
  expect(currentEvent.from_address).to.eql(event.from_address);
  // Needs deep equality for array, can't do to.equal
  expect(currentEvent.data).to.eql(event.data);
}

async function expectEventWhile(event: Event, fn: () => Promise<InvokeFunctionResponse>) {
  const { transaction_hash } = await fn();
  await expectEvent(transaction_hash, event);
}

export { declareContract, loadContract, expectRevertWithErrorMessage, expectEvent, expectEventWhile };
