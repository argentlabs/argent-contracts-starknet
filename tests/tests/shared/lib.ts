import { assert, expect } from "chai";
import { readFileSync } from "fs";
import {
  CompiledSierra,
  CompiledSierraCasm,
  Contract,
  DeclareContractPayload,
  InvokeTransactionReceiptResponse,
  hash,
  json,
  shortString,
} from "starknet";

import { account, provider } from "./constants";

const classHashCache: { [contractName: string]: string } = {};

async function isClassHashDeclared(classHash: string): Promise<boolean> {
  try {
    await provider.getClassByHash(classHash);
    // class already declared
    return true;
  } catch (e) {
    // class not declared, go on
    return false;
  }
}

// Could extends Account to add our specific fn but that's too early.
async function declareContract(contractName: string): Promise<string> {
  console.log(`\tDeclaring ${contractName}...`);
  const cachedClass = classHashCache[contractName];
  if (cachedClass) {
    return cachedClass;
  }
  const contract: CompiledSierra = json.parse(readFileSync(`./contracts/${contractName}.json`).toString("ascii"));
  const classHash = hash.computeContractClassHash(contract);
  if (await isClassHashDeclared(classHash)) {
    classHashCache[contractName] = classHash;
    return classHash;
  }
  if ("sierra_program" in contract) {
    const casm: CompiledSierraCasm = json.parse(readFileSync(`./contracts/${contractName}.casm`).toString("ascii"));
    const returnedClashHash = await actualDeclare({ contract, casm });
    expect(returnedClashHash).to.equal(classHash);
  } else {
    const returnedClashHash = await actualDeclare({ contract });
    expect(returnedClashHash).to.equal(classHash);
  }
  classHashCache[contractName] = classHash;
  return classHash;
}

async function actualDeclare(payload: DeclareContractPayload): Promise<string> {
  const hash = await account
    .declare(payload, { maxFee: 1e18 }) // max fee avoids slow estimate
    .then(async (deployResponse) => {
      await account.waitForTransaction(deployResponse.transaction_hash);
      return deployResponse.class_hash;
    })
    .catch((e) => {
      return extractHashFromErrorOrCrash(e);
    });
  console.log(`\t\t✅ Declared at ${hash}`);
  return hash;
}

async function loadContract(contract_address: string) {
  const { abi: testAbi } = await provider.getClassAt(contract_address);
  if (!testAbi) {
    throw new Error("Error while getting ABI");
  }
  return new Contract(testAbi, contract_address, provider);
}

async function expectRevertWithErrorMessage(errorMessage: string, fn: () => void) {
  try {
    await fn();
    assert.fail("No error detected");
  } catch (e: any) {
    expect(e.toString()).to.contain(shortString.encodeShortString(errorMessage));
  }
}

async function expectEvent(transactionHash: string, eventName: string, data: string[] = []) {
  const txReceiptDeployTest: InvokeTransactionReceiptResponse = await provider.waitForTransaction(transactionHash);
  if (!txReceiptDeployTest.events) {
    assert.fail("No events triggered");
  }
  const selector = hash.getSelectorFromName(eventName);
  const event = txReceiptDeployTest.events.filter((e) => e.keys[0] == selector);
  if (event.length == 0) {
    assert.fail(`No event detected in this transaction: ${transactionHash}`);
  }
  if (event.length > 1) {
    assert.fail("Unsupported: Multiple events with same selector detected");
  }
  // Needs deep equality for array, can't do to.equal
  expect(event[0].data).to.eql(data);
}

function extractHashFromErrorOrCrash(e: string) {
  const hashRegex = /hash\s+(0x[a-fA-F\d]+)/;
  const matches = e.toString().match(hashRegex);
  if (matches !== null) {
    return matches[1];
  } else {
    throw e;
  }
}

export { declareContract, loadContract, expectRevertWithErrorMessage, expectEvent };
