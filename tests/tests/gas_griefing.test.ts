import {
  ArgentSigner,
  declareContract,
  deployAccount,
  expectExecutionRevert,
  loadContract,
  randomPrivateKey,
  waitForExecution,
} from "./shared";

describe("Gas griefing", function () {
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Block guardian attempts", async function () {
    const accountSigner = new ArgentSigner(randomPrivateKey(), randomPrivateKey());
    const guardianOnlySigner = new ArgentSigner(accountSigner.guardianPrivateKey);

    const account = await deployAccount(
      argentAccountClassHash,
      accountSigner.ownerPrivateKey,
      accountSigner.guardianPrivateKey,
    );

    const accountContract = await loadContract(account.address);
    account.signer = guardianOnlySigner;

    await expectExecutionRevert("argent/max-fee-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(randomPrivateKey()), undefined, {
        maxFee: 60000000000000000n,
      }),
    );

    for (let attempt = 1; attempt <= 5; attempt++) {
      await waitForExecution(
        account.execute(accountContract.populateTransaction.trigger_escape_owner(randomPrivateKey())),
      );
    }
    await expectExecutionRevert("argent/max-escape-attempts", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(randomPrivateKey())),
    );
  });

  it("Block high fee", async function () {
    const accountSigner = new ArgentSigner(randomPrivateKey(), randomPrivateKey());
    const guardianOnlySigner = new ArgentSigner(accountSigner.guardianPrivateKey);

    const account = await deployAccount(
      argentAccountClassHash,
      accountSigner.ownerPrivateKey,
      accountSigner.guardianPrivateKey,
    );

    const accountContract = await loadContract(account.address);
    account.signer = guardianOnlySigner;
    await expectExecutionRevert("argent/max-fee-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(randomPrivateKey()), undefined, {
        maxFee: 60000000000000000,
      }),
    );
  });
});
