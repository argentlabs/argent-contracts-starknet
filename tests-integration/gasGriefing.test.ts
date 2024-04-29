import { RPC, num } from "starknet";
import {
  ArgentSigner,
  deployAccount,
  ensureSuccess,
  expectExecutionRevert,
  randomStarknetKeyPair,
  waitForTransaction,
} from "../lib";

describe("Gas griefing", function () {
  this.timeout(320000);

  // run test with both TxV1 and TxV3
  for (const useTxV3 of [false, true]) {
    it(`Block guardian attempts (TxV3:${useTxV3})`, async function () {
      const { account, guardian, accountContract } = await deployAccount({ useTxV3 });
      account.signer = new ArgentSigner(guardian);

      await waitForTransaction(await accountContract.trigger_escape_owner(randomStarknetKeyPair().compiledSigner));
      await expectExecutionRevert("argent/last-escape-too-recent", () =>
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
    await expectExecutionRevert("argent/max-fee-too-high", () =>
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
    const estimate = await accountContract.estimateFee.trigger_escape_owner(compiledSigner);

    const l1_gas = BigInt(
      estimate.resourceBounds.l1_gas.max_amount * estimate.resourceBounds.l1_gas.max_price_per_unit,
    );
    const newResourceBounds = {
      ...estimate.resourceBounds,
      l2_gas: {
        ...estimate.resourceBounds.l2_gas,
        // Need (max_amount * max_price_per_unit) + (tip * max_amount)> 5e18
        max_amount: num.toHexString(1000000000000000000n - l1_gas / 5n + 1n), // we can't use 1e18, not enough precision
        max_price_per_unit: num.toHexString(4),
      },
    };
    // This makes exactly 0x4563918244f40005 = 5e18 + 5
    await expectExecutionRevert("argent/max-fee-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), undefined, {
        resourceBounds: newResourceBounds,
        tip: 1,
      }),
    );
  });

  it("Doesn't block high fee TxV3 when just under", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      useTxV3: true,
    });
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();
    const estimate = await accountContract.estimateFee.trigger_escape_owner(compiledSigner);

    const l1_gas = estimate.resourceBounds.l1_gas.max_amount * estimate.resourceBounds.l1_gas.max_price_per_unit;
    const newResourceBounds = {
      ...estimate.resourceBounds,
      l2_gas: {
        ...estimate.resourceBounds.l2_gas,
        // Need (max_amount * max_price_per_unit) + (tip * max_amount)<= 5e18
        max_amount: num.toHexString(1e18 - l1_gas / 5), // Here precision is just good enough
        max_price_per_unit: num.toHexString(4),
      },
    };
    // This makes exactly 0x4563918244f40000 = 5e18
    ensureSuccess(
      await waitForTransaction(
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), undefined, {
          resourceBounds: newResourceBounds,
          tip: 1,
        }),
      ),
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
    await expectExecutionRevert("argent/tip-too-high", () =>
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), undefined, {
        resourceBounds: newResourceBounds,
        tip: tipInStrkPerL2Gas,
      }),
    );
  });

  it("Block other DA modes", async function () {
    const { account, accountContract, guardian } = await deployAccount({ useTxV3: true });
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert("argent/invalid-da-mode", () =>
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        undefined,
        {
          nonceDataAvailabilityMode: RPC.EDataAvailabilityMode.L2,
        },
      ),
    );
    await expectExecutionRevert("argent/invalid-da-mode", () =>
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
    await expectExecutionRevert("argent/invalid-deployment-data", () =>
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
