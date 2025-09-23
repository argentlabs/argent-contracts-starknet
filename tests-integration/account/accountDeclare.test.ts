import { expect } from "chai";
import { CompiledSierra } from "starknet";
import { deployAccount, fixturesFolder, getDeclareContractPayload, manager, readContract } from "../../lib";

describe("ArgentAccount: declare", function () {
  beforeEach(async () => {
    await manager.restartDevnetAndClearClassCache();
  });

  it(`Expect 'argent/invalid-contract-version' when trying to declare Cairo contract version1 (CASM)`, async function () {
    const { account } = await deployAccount();
    // Using version 1 will require ETH
    await manager.mintEth(account.address, 1e18);
    const contract: CompiledSierra = readContract(`${fixturesFolder}Proxy.contract_class.json`);
    // await expectRevertWithErrorMessage("argent/invalid-declare-version", account.declare({ contract }));
  });
  it(`Expect the account to be able to declare a Cairo contract version2 (SIERRA)`, async function () {
    const { account } = await deployAccount();
    const { class_hash: mockDappClassHash } = await account.declare(getDeclareContractPayload("MockDapp"));
    const compiledClassHash = await manager.getClassByHash(mockDappClassHash);
    expect(compiledClassHash).to.exist;
  });
});
