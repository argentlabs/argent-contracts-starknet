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

describe("Gas griefing", function () {
  this.timeout(320000);

  before(async () => {
    await restartDevnetIfTooLong();
  });

  it("Block guardian attempts", async function () {
    const { account, guardian, accountContract } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    for (let attempt = 1; attempt <= 5; attempt++) {
      await waitForTransaction(await accountContract.trigger_escape_owner(randomKeyPair().publicKey));
    }
    await expectExecutionRevert("argent/max-escape-attempts", () =>
      accountContract.trigger_escape_owner(randomKeyPair().publicKey),
    );
  });

  it("Block high fee", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    await fundAccount(account.address, 50000000000000001n, "ETH");
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert("argent/max-fee-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(randomKeyPair().publicKey), undefined, {
        maxFee: "50000000000000001",
      }),
    );
  });
});
