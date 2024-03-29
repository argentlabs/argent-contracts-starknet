import { expect } from "chai";
import { CompiledSierra } from "starknet";
import {
  declareContract,
  deployAccount,
  expectRevertWithErrorMessage,
  fixturesFolder,
  getDeclareContractPayload,
  provider,
  readContract,
  restartDevnet,
} from "./lib";

describe("ArgentAccount: declare", function () {
  beforeEach(async () => {
    await restartDevnet();
  });
  for (const useTxV3 of [false, true]) {
    it(`Expect 'argent/invalid-contract-version' when trying to declare Cairo contract version1 (CASM) (TxV3: ${useTxV3})`, async function () {
      const { account } = await deployAccount({ useTxV3 });
      const contract: CompiledSierra = readContract(`${fixturesFolder}Proxy.contract_class.json`);
      expectRevertWithErrorMessage("argent/invalid-tx-version", () => account.declare({ contract }));
    });

    it(`Expect the account to be able to declare a Cairo contract version2 (SIERRA) (TxV3:${useTxV3})`, async function () {
      const { account } = await deployAccount({ useTxV3 });
      const { class_hash: testDappClassHash } = await account.declare(getDeclareContractPayload("TestDapp"));
      const compiledClassHash = await provider.getClassByHash(testDappClassHash);
      expect(compiledClassHash).to.exist;
    });
  }
});
