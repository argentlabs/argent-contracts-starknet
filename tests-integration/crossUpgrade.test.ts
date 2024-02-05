import { declareContract, deployAccount, expectRevertWithErrorMessage, upgradeAccount } from "./lib";
import { deployMultisig1_1 } from "./lib/multisig";

describe("Upgrades to a different account type", function () {
  it("Upgrade Account to Multisig should fail", async function () {
    const { account } = await deployAccount();
    await expectRevertWithErrorMessage("argent/invalid-threshold", async () =>
      upgradeAccount(account, await declareContract("ArgentMultisig")),
    );
  });

  it("Upgrade Multisig to Account should fail", async function () {
    const { account } = await deployMultisig1_1();
    await expectRevertWithErrorMessage("argent/null-owner", async () =>
      upgradeAccount(account, await declareContract("ArgentAccount")),
    );
  });
});
