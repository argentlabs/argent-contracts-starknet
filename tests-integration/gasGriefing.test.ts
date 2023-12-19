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
import { num } from "starknet";
describe("Gas griefing", function () {
  this.timeout(320000);

  before(async () => {
    await restartDevnetIfTooLong();
  });

  // run test with both TxV1 and TxV3
  for (const useTxV3 of [false, true]) {
    it(`Block guardian attempts (TxV3:${useTxV3})`, async function () {
      const { account, guardian, accountContract } = await deployAccount({ useTxV3 });
      account.signer = new ArgentSigner(guardian);

      for (let attempt = 1; attempt <= 5; attempt++) {
        await waitForTransaction(await accountContract.trigger_escape_owner(randomKeyPair().publicKey));
      }
      await expectExecutionRevert("argent/max-escape-attempts", () =>
        accountContract.trigger_escape_owner(randomKeyPair().publicKey),
      );
    });
  }

  it("Block high fee TxV1", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      selfDeploy: false,
      useTxV3: false,
      fundingAmount: 50000000000000001n,
    });
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert("argent/max-fee-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(randomKeyPair().publicKey), undefined, {
        maxFee: "50000000000000001",
      }),
    );
  });

  it("Block high fee TxV3", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      selfDeploy: false,
      useTxV3: true,
      fundingAmount: 50000000000000001n,
    });
    account.signer = new ArgentSigner(guardian);

    const newOwnerPubKey = randomKeyPair().publicKey;
    const estimate = await accountContract.estimateFee.trigger_escape_owner(newOwnerPubKey);

    const maxEscapeTip = 1000000000000000000n;
    const maxL2GasAmount = 10n;
    const newResourceBounds = {
      ...estimate.resourceBounds,
      l2_gas: {
        ...estimate.resourceBounds.l2_gas,
        max_amount: num.toHexString(maxL2GasAmount),
      },
    };
    const targetTip = maxEscapeTip + 1n;
    const tipInStrkPerL2Gas = (targetTip / maxL2GasAmount) + 1n;
    await expectExecutionRevert("argent/tip-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(newOwnerPubKey), undefined, {
        resourceBounds: newResourceBounds,
        tip: tipInStrkPerL2Gas,
      }),
    );
  });
});
