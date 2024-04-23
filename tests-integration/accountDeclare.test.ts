import { expect } from "chai";
import { CompiledSierra } from "starknet";
import {
  deployAccount,
  expectRevertWithErrorMessage,
  fixturesFolder,
  getDeclareContractPayload,
  mintEth,
  provider,
  readContract,
  restartDevnet,
} from "../lib";

describe("ArgentAccount: declare", function () {
  beforeEach(async () => {
    await restartDevnet();
  });

  for (const useTxV3 of [false, true]) {
    it(`Expect 'argent/invalid-contract-version' when trying to declare Cairo contract version1 (CASM) (TxV3: ${useTxV3})`, async function () {
      const { account } = await deployAccount({ useTxV3 });
      // Using version 1 will require ETH
      mintEth(account.address, 1e18);
      const contract: CompiledSierra = readContract(`${fixturesFolder}Proxy.contract_class.json`);
      await expectRevertWithErrorMessage("argent/invalid-declare-version", () =>
        account.declare({ contract }, { version: "0x1" }),
      );
    });

    it(`Expect the account to be able to declare a Cairo contract version2 (SIERRA) (TxV3:${useTxV3})`, async function () {
      const { account } = await deployAccount({ useTxV3 });
      const { class_hash: mockDappClassHash } = await account.declare(getDeclareContractPayload("MockDapp"));
      const compiledClassHash = await provider.getClassByHash(mockDappClassHash);
      expect(compiledClassHash).to.exist;
    });
  }
});
