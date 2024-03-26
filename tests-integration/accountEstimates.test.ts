import { uint256 } from "starknet";
import {
  deployAccount,
  expectRevertWithErrorMessage,
  getEthContract,
  provider,
  ArgentSigner,
  ArgentAccount,
  Eip191KeyPair,
  getStrkContract,
  EstimateStarknetKeyPair,
  StarknetKeyPair,
  EstimateEip191KeyPair,
  deployMultisig1_3,
  MultisigSigner,
} from "./lib";

describe("Estimates", function () {
  describe("ArgentAccount", function () {
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
        estimateAccount.execute(call, undefined, { ...estimate }),
      );
      await account.execute(call, undefined, { ...estimate });
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
        estimateAccount.execute(call, undefined, { ...estimate }),
      );
      await account.execute(call, undefined, { ...estimate });
    });
  });

  describe("Multisig", function () {
    it(`Should be able to estimate using the wrong signature but fail execution`, async function () {
      const { account, keys } = await deployMultisig1_3();

      const estimateSigner = new MultisigSigner([new EstimateStarknetKeyPair((keys[0] as StarknetKeyPair).publicKey)]);
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
      await expectRevertWithErrorMessage("argent/invalid-signature", () =>
        estimateAccount.execute(call, undefined, { ...estimate }),
      );
      await account.execute(call, undefined, { ...estimate });
    });

    it(`Using txv3`, async function () {
      const { account, keys } = await deployMultisig1_3({ useTxV3: true });

      const estimateSigner = new MultisigSigner([new EstimateStarknetKeyPair((keys[0] as StarknetKeyPair).publicKey)]);
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
      await expectRevertWithErrorMessage("argent/invalid-signature", () =>
        estimateAccount.execute(call, undefined, { ...estimate }),
      );
      await account.execute(call, undefined, { ...estimate });
    });
  });
});
