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
  manager,
} from "../../lib";

const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);

describe("Estimates", function () {
  describe("ArgentAccount", function () {
    it(`Should be able to estimate using the wrong signature but fail execution using txv3`, async function () {
      const { account, owner, guardian } = await deployAccount();

      const estimateSigner = new ArgentSigner(
        new EstimateStarknetKeyPair((owner as StarknetKeyPair).publicKey),
        new EstimateStarknetKeyPair((guardian as StarknetKeyPair).publicKey),
      );
      const estimateAccount = new ArgentAccount(manager, account.address, estimateSigner);
      const call = (await manager.tokens.feeTokenContract()).populateTransaction.transfer(recipient, amount);

      const estimate = await estimateAccount.estimateInvokeFee(call, { skipValidate: false });
      await expectRevertWithErrorMessage("argent/invalid-owner-sig", estimateAccount.execute(call, { ...estimate }));
      await account.execute(call, { ...estimate });
    });

    it(`Using Eip191Signer`, async function () {
      const { account, guardian, owner } = await deployAccount({ owner: new Eip191KeyPair() });

      const estimateSigner = new ArgentSigner(
        new EstimateEip191KeyPair((owner as Eip191KeyPair).address),
        new EstimateStarknetKeyPair((guardian as StarknetKeyPair).publicKey),
      );
      const estimateAccount = new ArgentAccount(manager, account.address, estimateSigner);
      const call = (await manager.tokens.feeTokenContract()).populateTransaction.transfer(recipient, amount);
      const estimate = await estimateAccount.estimateInvokeFee(call, { skipValidate: false });
      await expectRevertWithErrorMessage("argent/invalid-owner-sig", estimateAccount.execute(call, { ...estimate }));
      await account.execute(call, { ...estimate });
    });
  });

  describe("Multisig", function () {
    it(`Should be able to estimate using the wrong signature but fail execution`, async function () {
      const { account, keys } = await deployMultisig1_3({});

      const estimateSigner = new MultisigSigner([new EstimateStarknetKeyPair((keys[0] as StarknetKeyPair).publicKey)]);
      const estimateAccount = new ArgentAccount(manager, account.address, estimateSigner);
      const call = (await manager.tokens.feeTokenContract()).populateTransaction.transfer(recipient, amount);

      const estimate = await estimateAccount.estimateInvokeFee(call, { skipValidate: false });
      await expectRevertWithErrorMessage("argent/invalid-signature", estimateAccount.execute(call, { ...estimate }));
      await account.execute(call, { ...estimate });
    });

    it(`Use Eip191Signer using txv3`, async function () {
      const { account, keys } = await deployMultisig1_3({ keys: [new Eip191KeyPair()] });

      const estimateSigner = new MultisigSigner([new EstimateEip191KeyPair((keys[0] as Eip191KeyPair).address)]);
      const estimateAccount = new ArgentAccount(manager, account.address, estimateSigner);
      const call = (await manager.tokens.feeTokenContract()).populateTransaction.transfer(recipient, amount);
      const estimate = await estimateAccount.estimateInvokeFee(call, { skipValidate: false });
      await expectRevertWithErrorMessage("argent/invalid-signature", estimateAccount.execute(call, { ...estimate }));
      await account.execute(call, { ...estimate });
    });
  });
});
