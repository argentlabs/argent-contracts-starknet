import { expect } from "chai";
import { CallData } from "starknet";
import {
  deployMultisig1_1,
  deployMultisig1_3,
  expectEvent,
  expectRevertWithErrorMessage,
  randomStarknetKeyPair,
  zeroStarknetSignatureType,
} from "./lib";

describe("ArgentMultisig: signer storage", function () {
  describe("add_signers(new_threshold, signers_to_add)", function () {
    describe("Test all possible revert errors when adding signers", function () {
      it("Expect 'argent/already-a-signer' if adding an owner already in the list", async function () {
        const { accountContract, keys, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/already-a-signer", () =>
          accountContract.add_signers(CallData.compile([threshold, [keys[1].signer]])),
        );
      });

      it("Expect deserialization error when adding a zero signer", async function () {
        const { accountContract, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
          accountContract.add_signers(CallData.compile([threshold, [zeroStarknetSignatureType()]])),
        );
      });

      it("Expect 'bad/invalid-threshold' if changing to a zero threshold", async function () {
        const { accountContract } = await deployMultisig1_3();

        const { signer } = randomStarknetKeyPair();

        await expectRevertWithErrorMessage("argent/invalid-threshold", () =>
          accountContract.add_signers(CallData.compile([0, [signer]])),
        );
      });

      it("Expect 'bad/invalid-threshold' if threshold > no. owners", async function () {
        const { accountContract, keys } = await deployMultisig1_3();

        const { signer } = randomStarknetKeyPair();

        await expectRevertWithErrorMessage("argent/bad-threshold", () =>
          accountContract.add_signers(CallData.compile([keys.length + 2, [signer]])),
        );
      });
    });
  });

  describe("remove_signers(new_threshold, signers_to_remove)", function () {
    const signersToRemove = [[0], [1], [2], [0, 1], [1, 0], [0, 2], [2, 0], [1, 2], [2, 1]];
    it("Should remove first signer and update threshold", async function () {
      const { accountContract, keys } = await deployMultisig1_3();

      const newThreshold = 2n;

      const { transaction_hash } = await accountContract.remove_signers(
        CallData.compile([newThreshold, [keys[0].signer]]),
      );

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "ThresholdUpdated",
        data: CallData.compile([newThreshold]),
      });

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerRemoved",
        additionalKeys: [keys[0].guid.toString()],
      });

      await accountContract.is_signer_guid(keys[0].guid).should.eventually.be.false;
      await accountContract.get_threshold().should.eventually.equal(newThreshold);
    });

    for (const testCase of signersToRemove) {
      const indicesToRemove = testCase.join(", ");
      it(`Removing at index(es): ${indicesToRemove}`, async function () {
        const { accountContract, keys, threshold } = await deployMultisig1_3();

        await accountContract.remove_signers(
          CallData.compile([threshold, testCase.map((index) => keys[index].signer)]),
        );

        for (const signerIndex of testCase) {
          await accountContract.is_signer_guid(keys[signerIndex].guid).should.eventually.be.false;
        }
        const remainingSigners = keys.filter((_, index) => !testCase.includes(index));
        for (const keyPair of remainingSigners) {
          await accountContract.is_signer_guid(keyPair.guid).should.eventually.be.true;
        }

        await accountContract.get_threshold().should.eventually.equal(threshold);
      });
    }

    describe("Test all possible revert errors when removing signers", function () {
      it("Expect 'argent/not-a-signer' when replacing an owner not in the list", async function () {
        const { signer: nonSigner } = randomStarknetKeyPair();

        const { accountContract, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/not-a-signer", () =>
          accountContract.remove_signers(CallData.compile([threshold, [nonSigner]])),
        );
      });

      it("Expect deserialization error when removing a 0 signer", async function () {
        const { accountContract, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
          accountContract.remove_signers(CallData.compile([threshold, [zeroStarknetSignatureType()]])),
        );
      });

      it("Expect argent/bad-threshold if threshold > no.of owners", async function () {
        const { accountContract, keys } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/bad-threshold", () =>
          accountContract.remove_signers(CallData.compile([3, [keys[1].signer]])),
        );
      });

      it("Expect argent/invalid-threshold when changing to a zero threshold ", async function () {
        const { accountContract, keys } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/invalid-threshold", () =>
          accountContract.remove_signers(CallData.compile([0, [keys[1].signer]])),
        );
      });
    });
  });

  describe("Expect revert messages under different conditions when trying to replace an owner", function () {
    it("Expect deserialization error when replacing an owner with a zero signer", async function () {
      const { accountContract, keys } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
        accountContract.replace_signer(CallData.compile([keys[0].signer, zeroStarknetSignatureType()])),
      );
    });
  });
});
