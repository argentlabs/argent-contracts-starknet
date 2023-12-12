import {
  declareContract,
  deployAccount,
  expectRevertWithErrorMessage,
  upgradeAccount,
  restartDevnetIfTooLong,
} from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("Upgrades to a different account type", function () {
  let argentAccountClassHash: string;
  let multisigClassHash: string;

  before(async () => {
    await restartDevnetIfTooLong();
    argentAccountClassHash = await declareContract("ArgentAccount");
    multisigClassHash = await declareContract("ArgentMultisig");
  });

  it("Upgrade Account to Multisig should fail", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    await expectRevertWithErrorMessage("argent/invalid-threshold", () => upgradeAccount(account, multisigClassHash));
  });

  it("Upgrade Multisig to Account should fail", async function () {
    const { account } = await deployMultisig(multisigClassHash, 1, 1);
    await expectRevertWithErrorMessage("argent/null-owner", () => upgradeAccount(account, argentAccountClassHash));
  });
});
