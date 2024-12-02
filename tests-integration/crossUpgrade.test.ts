import { deployAccount, deployMultisig1_1, expectRevertWithErrorMessage, manager, upgradeAccount } from "../lib";

describe("Upgrades to a different account type", function () {
  it("Upgrade Account to Multisig should fail", async function () {
    const { account } = await deployAccount();
    await expectRevertWithErrorMessage(
      "argent/downgrade-not-allowed",
      upgradeAccount(account, await manager.declareLocalContract("ArgentMultisigAccount")),
    );
  });

  it("Upgrade Multisig to Account should fail", async function () {
    const { account } = await deployMultisig1_1();
    await expectRevertWithErrorMessage(
      "argent/invalid-name",
      upgradeAccount(account, await manager.declareLocalContract("ArgentAccount")),
    );
  });
});
