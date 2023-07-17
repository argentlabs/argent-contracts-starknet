import { expect } from "chai";
import { readFileSync } from "fs";
import { CompiledSierra, CompiledSierraCasm, json } from "starknet";
import {
  declareContract,
  deployAccount,
  dump,
  expectRevertWithErrorMessage,
  load,
  provider,
  removeFromCache,
  restart,
} from "./lib";

describe("ArgentAccount: declare", function () {
  let argentAccountClassHash: string;

  beforeEach(async () => {
    await dump();
    await restart();
    removeFromCache("ArgentAccount");
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  afterEach(async () => {
    await load();
  });

  it("Expect 'argent/invalid-contract-version' when trying to declare Cairo contract version1 (CASM) ", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    const contract: CompiledSierra = json.parse(
      readFileSync("./target/release/argent_contracts_Proxy.sierra.json").toString("ascii"),
    );
    expectRevertWithErrorMessage("argent/invalid-contract-version", () => account.declare({ contract }));
  });

  it("Expect the account to be able to declare a Cairo contract version2 (SIERRA)", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    const contract: CompiledSierra = json.parse(
      readFileSync("./target/release/argent_contracts_TestDapp.sierra.json").toString("ascii"),
    );
    const casm: CompiledSierraCasm = json.parse(
      readFileSync("./target/release/argent_contracts_TestDapp.casm.json").toString("ascii"),
    );
    const { class_hash, transaction_hash } = await account.declare({ contract, casm });
    await provider.waitForTransaction(transaction_hash);
    expect(provider.getCompiledClassByClassHash(class_hash)).to.exist;
  });
});
