import { uint256 } from "starknet";
import {
  deployAccount,
  expectRevertWithErrorMessage,
  getEthContract,
  randomStarknetKeyPair,
  provider,
  ArgentSigner,
  ArgentAccount,
  Eip191KeyPair,
  getStrkContract,
  EstimateStarknetKeyPair,
  StarknetKeyPair,
  EstimateEip191KeyPair,
} from "./lib";

describe("ArgentAccount: Estimates", function () {
  it(`Should be able to estimate using the wrong signature but fail execution`, async function () {
    const { account, owner, guardian } = await deployAccount({ useTxV3: false });

    const estimateSigner = new ArgentSigner(
      new EstimateStarknetKeyPair((owner as StarknetKeyPair).publicKey),
      new EstimateStarknetKeyPair((guardian as StarknetKeyPair).publicKey),
    );
    const estimateAccount = new ArgentAccount(
      provider,
      account.address,
      estimateSigner,
      "1",
      account.transactionVersion,
    );
    const recipient = "0xadbe1";
    const call = (await getEthContract()).populateTransaction.transfer(recipient, uint256.bnToUint256(1));

    const estimate = await estimateAccount.estimateFee(call, { skipValidate: false });
    await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
      estimateAccount.execute(call, undefined, {
        resourceBounds: estimate.resourceBounds,
        maxFee: estimate.suggestedMaxFee,
      }),
    );
    await account.execute(call, undefined, {
      resourceBounds: estimate.resourceBounds,
      maxFee: estimate.suggestedMaxFee,
    });
  });

  it(`Use Eip191Signer and txv3`, async function () {
    const { account, guardian, owner } = await deployAccount({ owner: new Eip191KeyPair(), useTxV3: true });

    const estimateSigner = new ArgentSigner(
      new EstimateEip191KeyPair((owner as Eip191KeyPair).address),
      new EstimateStarknetKeyPair((guardian as StarknetKeyPair).publicKey),
    );
    const estimateAccount = new ArgentAccount(
      provider,
      account.address,
      estimateSigner,
      "1",
      account.transactionVersion,
    );
    const recipient = "0xadbe1";
    const call = (await getStrkContract()).populateTransaction.transfer(recipient, uint256.bnToUint256(1));
    const estimate = await estimateAccount.estimateFee(call, { skipValidate: false });
    await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
      estimateAccount.execute(call, undefined, {
        resourceBounds: estimate.resourceBounds,
        maxFee: estimate.suggestedMaxFee,
      }),
    );
    await account.execute(call, undefined, {
      resourceBounds: estimate.resourceBounds,
      maxFee: estimate.suggestedMaxFee,
    });
  });
});
