import { expect } from "chai";
import { CompiledSierra } from "starknet";
import {
  declareContract,
  deployAccount,
  dump,
  expectRevertWithErrorMessage,
  fixturesFolder,
  load,
  provider,
  readContract,
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
    const contract: CompiledSierra = readContract(`${fixturesFolder}Proxy.contract_class.json`);
    expectRevertWithErrorMessage("argent/invalid-contract-version", () => account.declare({ contract }));
  });

  it("Expect the account to be able to declare a Cairo contract version2 (SIERRA)", async function () {
    const testDappClassHash = await declareContract("TestDapp");
    const compiledClassHash = await provider.getCompiledClassByClassHash(testDappClassHash);
    expect(compiledClassHash).to.exist;
    removeFromCache("TestDapp");
  });
});
