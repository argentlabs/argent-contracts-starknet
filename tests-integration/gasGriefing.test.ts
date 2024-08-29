import { RPC, num } from "starknet";
import { ArgentSigner, deployAccount, expectExecutionRevert, manager, randomStarknetKeyPair } from "../lib";

describe("Gas griefing", function () {
  this.timeout(320000);

  // run test with both TxV1 and TxV3
  for (const useTxV3 of [false, true]) {
    it(`Block guardian attempts (TxV3:${useTxV3})`, async function () {
      const { account, guardian, accountContract } = await deployAccount({ useTxV3 });
      account.signer = new ArgentSigner(guardian);

      await manager.waitForTx(accountContract.trigger_escape_owner(randomStarknetKeyPair().compiledSigner));
      await expectExecutionRevert(
        "argent/last-escape-too-recent",
        accountContract.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
      );
    });
  }

  it("Block high fee TxV1", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      useTxV3: false,
      fundingAmount: 50000000000000001n,
    });
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert(
      "argent/max-fee-too-high",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        undefined,
        {
          maxFee: "50000000000000001",
        },
      ),
    );
  });

  it("Block high fee TxV3", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      useTxV3: true,
    });
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();
    await manager.mintStrk(account.address, 6e18);

    // At the moment we should only use l1_gas, this simplifies the calculation
    const newResourceBounds = {
      l1_gas: {
        // Need (max_amount * max_price_per_unit) > 5e18
        max_amount: num.toHexString(5000000000000000000n / 36000000000n + 1n), // we can't use 1e18, not enough precision
        max_price_per_unit: num.toHexString(36000000000n),
      },
      l2_gas: {
        max_amount: "0x0",
        max_price_per_unit: "0x0",
      },
    };

    await expectExecutionRevert(
      "argent/max-fee-too-high",
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), undefined, {
        resourceBounds: newResourceBounds,
      }),
    );
  });

  it("Doesn't block high fee TxV3 when just under", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      useTxV3: true,
    });
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();
    await manager.mintStrk(account.address, 6e18);

    const newResourceBounds = {
      l1_gas: {
        // Need (max_amount * max_price_per_unit) <= 5e18
        max_amount: num.toHexString(5000000000000000000n / 36000000000n - 1n), // we can't use 1e18, not enough precision
        max_price_per_unit: num.toHexString(36000000000n),
      },
      l2_gas: {
        max_amount: "0x0",
        max_price_per_unit: "0x0",
      },
    };
    // This makes exactly 0x4563918244f40000 = 5e18
    await manager.ensureSuccess(
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), {
        resourceBounds: newResourceBounds,
      }),
    );
  });

  it("Block high tip TxV3", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      useTxV3: true,
      fundingAmount: 2000000000000000000n,
    });
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();
    const estimate = await accountContract.estimateFee.trigger_escape_owner(compiledSigner);

    const maxEscapeTip = 1000000000000000000n;
    // minimum amount of L2 gas allowed
    const maxL2GasAmount = 170n;
    const newResourceBounds = {
      ...estimate.resourceBounds,
      l2_gas: {
        ...estimate.resourceBounds.l2_gas,
        max_amount: num.toHexString(maxL2GasAmount),
      },
    };
    const targetTip = maxEscapeTip + 1n;
    const tipInStrkPerL2Gas = targetTip / maxL2GasAmount + 1n; // Add one to make sure it's rounded up
    await expectExecutionRevert(
      "argent/tip-too-high",
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), undefined, {
        resourceBounds: newResourceBounds,
        tip: tipInStrkPerL2Gas,
      }),
    );
  });

  it("Block other DA modes", async function () {
    const { account, accountContract, guardian } = await deployAccount({ useTxV3: true });
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert(
      "argent/invalid-da-mode",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        undefined,
        {
          nonceDataAvailabilityMode: RPC.EDataAvailabilityMode.L2,
        },
      ),
    );
    await expectExecutionRevert(
      "argent/invalid-da-mode",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        undefined,
        {
          feeDataAvailabilityMode: RPC.EDataAvailabilityMode.L2,
        },
      ),
    );
  });

  it("Block deployment data", async function () {
    const { account, accountContract, guardian } = await deployAccount({ useTxV3: true });
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert(
      "argent/invalid-deployment-data",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        undefined,
        {
          accountDeploymentData: ["0x1"],
        },
      ),
    );
  });
});
