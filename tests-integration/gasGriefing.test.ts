import {
  ArgentSigner,
  declareContract,
  deployAccount,
  expectExecutionRevert,
  fundAccount,
  randomKeyPair,
  waitForTransaction,
  restartDevnetIfTooLong,
} from "./lib";
import { assert, expect } from "chai";

describe("Gas griefing", function () {
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    await restartDevnetIfTooLong();
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Block guardian attempts", async function () {
    const { account, guardian, accountContract } = await deployAccount(argentAccountClassHash);
    account.signer = new ArgentSigner(guardian);

    for (let attempt = 1; attempt <= 5; attempt++) {
      await waitForTransaction(await accountContract.trigger_escape_owner(randomKeyPair().publicKey));
    }
    await expectExecutionRevert("argent/max-escape-attempts", () =>
      accountContract.trigger_escape_owner(randomKeyPair().publicKey),
    );
  });

  it("Block high fee", async function () {
    const { account, accountContract, guardian } = await deployAccount(argentAccountClassHash);
    await fundAccount(account.address, 50000000000000001n);
    account.signer = new ArgentSigner(guardian);
    // catching the revert message 'argent/max-fee-too-high' would be better but it's not returned by the RPC
    expect(
      account.execute(accountContract.populateTransaction.trigger_escape_owner(randomKeyPair().publicKey), undefined, {
        maxFee: "50000000000000001",
      }),
    ).to.be.rejectedWith("Account validation failed");
  });
});
