import { uint256 } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  Eip191KeyPair,
  EstimateEip191KeyPair,
  EstimateStarknetKeyPair,
  MultisigSigner,
  StarknetKeyPair,
  deployAccount,
  deployMultisig1_3,
  expectRevertWithErrorMessage,
  getFeeTokenContract,
  provider,
} from "./lib";

const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);

describe("Estimates", function () {
  for (const useTxV3 of [false, true]) {
    describe("ArgentAccount", function () {
      it(`Should be able to estimate using the wrong signature but fail execution using txv3: ${useTxV3}`, async function () {
        const { account, owner, guardian } = await deployAccount({ useTxV3 });

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
        const call = (await getFeeTokenContract(useTxV3)).populateTransaction.transfer(recipient, amount);

        const estimate = await estimateAccount.estimateFee(call, { skipValidate: false });
        await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
          estimateAccount.execute(call, undefined, { ...estimate }),
        );
        await account.execute(call, undefined, { ...estimate });
      });

      it(`Use Eip191Signer using txv3: ${useTxV3}`, async function () {
        const { account, guardian, owner } = await deployAccount({ owner: new Eip191KeyPair(), useTxV3 });

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
        const call = (await getFeeTokenContract(useTxV3)).populateTransaction.transfer(recipient, amount);
        const estimate = await estimateAccount.estimateFee(call, { skipValidate: false });
        await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
          estimateAccount.execute(call, undefined, { ...estimate }),
        );
        await account.execute(call, undefined, { ...estimate });
      });
    });

    describe("Multisig", function () {
      it(`Should be able to estimate using the wrong signature but fail execution`, async function () {
        const { account, keys } = await deployMultisig1_3({ useTxV3 });

        const estimateSigner = new MultisigSigner([
          new EstimateStarknetKeyPair((keys[0] as StarknetKeyPair).publicKey),
        ]);
        const estimateAccount = new ArgentAccount(
          provider,
          account.address,
          estimateSigner,
          "1",
          account.transactionVersion,
        );
        const call = (await getFeeTokenContract(useTxV3)).populateTransaction.transfer(recipient, amount);

        const estimate = await estimateAccount.estimateFee(call, { skipValidate: false });
        await expectRevertWithErrorMessage("argent/invalid-signature", () =>
          estimateAccount.execute(call, undefined, { ...estimate }),
        );
        await account.execute(call, undefined, { ...estimate });
      });

      it(`Use Eip191Signer using txv3: ${useTxV3}`, async function () {
        const { account, keys } = await deployMultisig1_3({ keys: [new Eip191KeyPair()], useTxV3 });

        const estimateSigner = new MultisigSigner([new EstimateEip191KeyPair((keys[0] as Eip191KeyPair).address)]);
        const estimateAccount = new ArgentAccount(
          provider,
          account.address,
          estimateSigner,
          "1",
          account.transactionVersion,
        );
        const call = (await getFeeTokenContract(useTxV3)).populateTransaction.transfer(recipient, amount);
        const estimate = await estimateAccount.estimateFee(call, { skipValidate: false });
        await expectRevertWithErrorMessage("argent/invalid-signature", () =>
          estimateAccount.execute(call, undefined, { ...estimate }),
        );
        await account.execute(call, undefined, { ...estimate });
      });
    });
  }
});
