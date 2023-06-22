import {
  ArgentSigner,
  declareContract,
  deployAccount,
  expectExecutionRevert,
  randomKeyPair,
  waitForTransaction,
} from "./lib";

describe("Gas griefing", function () {
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Block guardian attempts", async function () {
    const { account, guardian, IAccount } = await deployAccount(argentAccountClassHash);
    account.signer = new ArgentSigner(guardian?.privateKey);

    for (let attempt = 1; attempt <= 5; attempt++) {
      await waitForTransaction(await IAccount.trigger_escape_owner(randomKeyPair().publicKey));
    }
    await expectExecutionRevert("argent/max-escape-attempts", () =>
      IAccount.trigger_escape_owner(randomKeyPair().publicKey),
    );
  });

  it("Block high fee", async function () {
    const { account, IAccount, guardian } = await deployAccount(argentAccountClassHash);
    account.signer = new ArgentSigner(guardian?.privateKey);
    await expectExecutionRevert("argent/max-fee-too-high", () =>
      account.execute(IAccount.populateTransaction.trigger_escape_owner(randomKeyPair().publicKey), undefined, {
        maxFee: "60000000000000000",
      }),
    );
  });
});
