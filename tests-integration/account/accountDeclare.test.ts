import { expect } from "chai";
import {
  deployAccount,
  getDeclareContractPayload,
  manager,
} from "../../lib";

describe("ArgentAccount: declare", function () {
  beforeEach(async () => {
    await manager.restartDevnetAndClearClassCache();
  });

  it(`Expect the account to be able to declare a Cairo contract version2 (SIERRA)`, async function () {
    const { account } = await deployAccount();
    const { class_hash: mockDappClassHash } = await account.declare(getDeclareContractPayload("MockDapp"));
    const compiledClassHash = await manager.getClassByHash(mockDappClassHash);
    expect(compiledClassHash).to.exist;
  });
});
