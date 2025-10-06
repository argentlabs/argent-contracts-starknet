import { expect } from "chai";
import { EDataAvailabilityMode, ResourceBoundsBN } from "starknet";
import { ArgentSigner, deployAccount, expectExecutionRevert, manager, randomStarknetKeyPair } from "../lib";
import { l1DataGasPrice, l2GasPrice } from "../lib/gas";

const MAX_ESCAPE_MAX_FEE_STRK = 12000000000000000000n;

describe("Gas griefing", function () {
  it(`Block guardian attempts`, async function () {
    const { account, guardian, accountContract } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    await manager.waitForTx(accountContract.trigger_escape_owner(randomStarknetKeyPair().compiledSigner));
    await expectExecutionRevert(
      "argent/last-escape-too-recent",
      accountContract.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
    );
  });

  it("Block high fee TxV3", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();
    await manager.mintStrk(account.address, 16e18);

    const { resourceBounds } = await accountContract.estimateFee.trigger_escape_owner(compiledSigner);

    // At the moment we should only use l1_gas, this simplifies the calculation
    const newResourceBounds: ResourceBoundsBN = {
      l1_gas: {
        // Need (max_amount * max_price_per_unit) > 12e18
        max_amount: MAX_ESCAPE_MAX_FEE_STRK / resourceBounds.l1_gas.max_price_per_unit + 1n,
        max_price_per_unit: resourceBounds.l1_gas.max_price_per_unit,
      },
      l2_gas: {
        max_amount: 0n,
        max_price_per_unit: 0n,
      },
      l1_data_gas: {
        max_amount: 0n,
        max_price_per_unit: 0n,
      },
    };

    expect(getMaxFeeWithoutTip(newResourceBounds) > MAX_ESCAPE_MAX_FEE_STRK).to.be.true;
    await expectExecutionRevert(
      "argent/max-fee-too-high",
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), {
        resourceBounds: newResourceBounds,
        tip: 0,
      }),
    );
  });

  it("Doesn't block high fee TxV3 when just under", async function () {
    const { account, accountContract, guardian } = await deployAccount({ fundingAmount: 18e18 });
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();

    const { resourceBounds } = await accountContract.estimateFee.trigger_escape_owner(compiledSigner);

    // If this fails, we gotta update the math underneath
    expect(l1DataGasPrice < l2GasPrice).to.be.true;

    // Need that the sum of each bound (max_amount * max_price_per_unit) <= 12e18
    const l2Gas = {
      max_amount: resourceBounds.l2_gas.max_amount,
      max_price_per_unit: l2GasPrice,
    };
    const l2GasFee = l2Gas.max_price_per_unit * l2Gas.max_amount;
    const l1DataMaxAmount = (MAX_ESCAPE_MAX_FEE_STRK - l2GasFee) / l1DataGasPrice;
    const newResourceBounds = {
      ...resourceBounds,
      l2_gas: l2Gas,
      l1_data_gas: {
        max_amount: l1DataMaxAmount,
        max_price_per_unit: l1DataGasPrice,
      },
    };

    // Should be in-between MAX_ESCAPE_MAX_FEE_STRK - l1DataGasPrice and MAX_ESCAPE_MAX_FEE_STRK
    const maxFee = getMaxFeeWithoutTip(newResourceBounds);
    expect(maxFee <= MAX_ESCAPE_MAX_FEE_STRK).to.be.true;
    expect(maxFee >= MAX_ESCAPE_MAX_FEE_STRK - l1DataGasPrice).to.be.true;
    await manager.ensureSuccess(
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), {
        resourceBounds: newResourceBounds,
        tip: 0,
      }),
    );
  });

  it("Block high tip TxV3", async function () {
    const { account, accountContract, guardian } = await deployAccount({
      fundingAmount: 100e18,
    });
    account.signer = new ArgentSigner(guardian);

    const { compiledSigner } = randomStarknetKeyPair();
    const estimate = await accountContract.estimateFee.trigger_escape_owner(compiledSigner);

    const maxEscapeTip = 4000000000000000000n;

    const targetTip = maxEscapeTip + 1n;
    const tipInStrkPerL2Gas = targetTip / estimate.resourceBounds.l2_gas.max_amount + 1n; // Add one to make sure it's rounded up
    expect(tipInStrkPerL2Gas * estimate.resourceBounds.l2_gas.max_amount > maxEscapeTip).to.be.true;

    await expectExecutionRevert(
      "argent/tip-too-high",
      account.execute(accountContract.populateTransaction.trigger_escape_owner(compiledSigner), {
        tip: tipInStrkPerL2Gas,
      }),
    );
  });

  it("Block other DA modes", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert(
      "argent/invalid-da-mode",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        {
          nonceDataAvailabilityMode: EDataAvailabilityMode.L2,
        },
      ),
    );
    await expectExecutionRevert(
      "argent/invalid-da-mode",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        {
          feeDataAvailabilityMode: EDataAvailabilityMode.L2,
          tip: 0,
        },
      ),
    );
  });

  it("Block deployment data", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    account.signer = new ArgentSigner(guardian);
    await expectExecutionRevert(
      "argent/invalid-deployment-data",
      account.execute(
        accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
        {
          accountDeploymentData: ["0x1"],
          tip: 0,
        },
      ),
    );
  });
});

function getMaxFeeWithoutTip(resourceBounds: ResourceBoundsBN): bigint {
  let feeBound = 0n;
  for (const gasBound of Object.values(resourceBounds)) {
    feeBound += BigInt(gasBound.max_amount) * BigInt(gasBound.max_price_per_unit);
  }
  return feeBound;
}
