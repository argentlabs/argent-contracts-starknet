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
    it("Should add one new signer", async function () {
      const newSigner1 = randomStarknetKeyPair();
      const newSigner2 = randomStarknetKeyPair();
      const newSigner3 = randomStarknetKeyPair();

      const { accountContract, keys } = await deployMultisig1_1();
      await accountContract.is_signer_guid(keys[0].guid).should.eventually.be.true;
      await accountContract.is_signer_guid(newSigner1.publicKey).should.eventually.be.false;

      await accountContract.add_signers(CallData.compile([1, [newSigner1.signer]]));
      await accountContract.is_signer_guid(newSigner1.publicKey).should.eventually.be.true;

      const new_threshold = 2;

      const { transaction_hash } = await accountContract.add_signers(
        CallData.compile([new_threshold, [newSigner2.signer, newSigner3.signer]]),
      );

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "ThresholdUpdated",
        data: CallData.compile([new_threshold]),
      });

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerAdded",
        additionalKeys: [newSigner2.publicKey.toString()],
      });
      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerAdded",
        additionalKeys: [newSigner3.publicKey.toString()],
      });
      await accountContract.is_signer_guid(newSigner2.publicKey).should.eventually.be.true;
      await accountContract.is_signer_guid(newSigner3.publicKey).should.eventually.be.true;
      await accountContract.get_threshold().should.eventually.equal(BigInt(new_threshold));
    });

    describe("Test all possible revert errors when adding signers", function () {
      it("Expect 'argent/already-a-signer' if adding an owner already in the list", async function () {
        const { accountContract, keys, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/already-a-signer", () =>
          accountContract.add_signers(CallData.compile([threshold, [keys[1].signer]])),
        );
      });

      it("Expect 'argent/already-a-signer' if adding the same owner twice", async function () {
        const { accountContract, threshold } = await deployMultisig1_3();

        const newSigner1 = randomStarknetKeyPair().signer;

        await expectRevertWithErrorMessage("argent/already-a-signer", () =>
          accountContract.add_signers(CallData.compile([threshold, [newSigner1, newSigner1]])),
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

        const newSigner1 = randomStarknetKeyPair().signer;
        await expectRevertWithErrorMessage("argent/invalid-threshold", () =>
          accountContract.add_signers(CallData.compile([0, [newSigner1]])),
        );
      });

      it("Expect 'bad/invalid-threshold' if threshold > no. owners", async function () {
        const { accountContract, keys } = await deployMultisig1_3();

        const newSigner1 = randomStarknetKeyPair().signer;

        await expectRevertWithErrorMessage("argent/bad-threshold", () =>
          accountContract.add_signers(CallData.compile([keys.length + 2, [newSigner1]])),
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

    signersToRemove.forEach((testCase) => {
      const indicesToRemove = testCase.join(", ");
      it(`Removing at index(es): ${indicesToRemove}`, async function () {
        const { accountContract, keys, threshold } = await deployMultisig1_3();

        await accountContract.remove_signers(CallData.compile([threshold, testCase.map((index) => keys[index].signer)]));

        testCase.forEach(async (signerIndex) => {
          await accountContract.is_signer_guid(keys[signerIndex].guid).should.eventually.be.false;
        });
        keys;
        const remainingSigners = keys.filter((_, index) => !testCase.includes(index)).map(Number);
        remainingSigners.forEach(async (signerIndex) => {
          await accountContract.is_signer_guid(keys[signerIndex].guid).should.eventually.be.true;
        });

        await accountContract.get_threshold().should.eventually.equal(threshold);
      });
    });

    describe("Test all possible revert errors when removing signers", function () {
      it("Expect 'argent/not-a-signer' when replacing an owner not in the list", async function () {
        const nonSigner = randomStarknetKeyPair().signer;

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

      it("Expect 'argent/not-a-signer' removing the same owner twice in the same call", async function () {
        const { accountContract, keys, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/not-a-signer", () =>
          accountContract.remove_signers(CallData.compile([threshold, [keys[0].signer, keys[0].signer]])),
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
  describe("replace_signers(signer_to_remove, signer_to_add)", function () {
    it("Should replace one signer", async function () {
      const newSigner = randomStarknetKeyPair();

      const { accountContract, keys } = await deployMultisig1_1();

      const { transaction_hash } = await accountContract.replace_signer(CallData.compile([keys[0].signer, newSigner.signer]));

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerRemoved",
        additionalKeys: [keys[0].guid.toString()],
      });
      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerAdded",
        additionalKeys: [newSigner.guid.toString()],
      });
      await accountContract.is_signer_guid(newSigner.guid).should.eventually.be.true;
    });

    it("Should replace first signer", async function () {
      const newSigner = randomStarknetKeyPair();

      const { accountContract, keys } = await deployMultisig1_3();

      await accountContract.replace_signer(CallData.compile([keys[0].signer, newSigner.signer]));

      const signersList = await accountContract.get_signer_guids();
      expect(signersList).to.have.ordered.members([newSigner.guid, keys[1].guid, keys[2].guid]);
    });

    it("Should replace middle signer", async function () {
      const newSigner = randomStarknetKeyPair();

      const { accountContract, keys } = await deployMultisig1_3();

      await accountContract.replace_signer(CallData.compile([keys[1].signer, newSigner.signer]));

      const signersList = await accountContract.get_signer_guids();
      expect(signersList).to.have.ordered.members([keys[0].guid, newSigner.guid, keys[2].guid]);
    });

    it("Should replace last signer", async function () {
      const newSigner = randomStarknetKeyPair();

      const { accountContract, keys } = await deployMultisig1_3();

      await accountContract.replace_signer(CallData.compile([keys[2].signer, newSigner.signer]));

      const signersList = await accountContract.get_signer_guids();
      expect(signersList).to.have.ordered.members([keys[0].guid, keys[1].guid, newSigner.guid]);
    });
  });
  describe("Expect revert messages under different conditions when trying to replace an owner", function () {
    it("Expect 'argent/not-a-signer' when trying to replace a signer that isn't in the list", async function () {
      const nonSigner = randomStarknetKeyPair().signer;
      const newSigner = randomStarknetKeyPair().signer;

      const { accountContract } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.replace_signer(CallData.compile([nonSigner, newSigner])),
      );
    });
    it("Expect 'argent/already-a-signer' when replacing an owner with one already in the list", async function () {
      const { accountContract, keys } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/already-a-signer", () =>
        accountContract.replace_signer(CallData.compile([keys[0].signer, keys[1].signer])),
      );
    });
    it("Expect 'argent/already-a-signer' when replacing an owner with themselves", async function () {
      const { accountContract, keys } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/already-a-signer", () =>
        accountContract.replace_signer(CallData.compile([keys[0].signer, keys[0].signer])),
      );
    });
    it("Expect deserialization error when replacing an owner with a zero signer", async function () {
      const { accountContract, keys } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
        accountContract.replace_signer(CallData.compile([keys[0].signer, zeroStarknetSignatureType()])),
      );
    });
  });
  describe("change threshold", function () {
    it("change threshold", async function () {
      const { accountContract, threshold } = await deployMultisig1_3();

      const initialThreshold = await accountContract.get_threshold();
      expect(initialThreshold).to.equal(threshold);

      const newThreshold = 2n;
      const { transaction_hash } = await accountContract.change_threshold(newThreshold);
      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "ThresholdUpdated",
        data: CallData.compile([newThreshold]),
      });
      const updatedThreshold = await accountContract.get_threshold();
      expect(updatedThreshold).to.be.equal(newThreshold);
    });

    it("Expect 'argent/bad-threshold' if threshold > no. owners", async function () {
      const { accountContract, keys } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/bad-threshold", () =>
        accountContract.change_threshold(keys.length + 1),
      );
    });
    it("Expect 'argent/invalid-threshold' if threshold set to 0", async function () {
      const { accountContract } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/invalid-threshold", () => accountContract.change_threshold(0));
    });
  });
});
