import { expect } from "chai";
import { CallData } from "starknet";
import {
  deployMultisig1_1,
  deployMultisig1_3,
  expectEvent,
  expectRevertWithErrorMessage,
  randomKeyPair,
  starknetSigner,
  intoGuid,
} from "./lib";

describe("ArgentMultisig: signer storage", function () {
  describe("add_signers(new_threshold, signers_to_add)", function () {
    it("Should add one new signer", async function () {
      const newSigner1 = randomKeyPair().publicKey;
      const newSigner2 = randomKeyPair().publicKey;
      const newSigner3 = randomKeyPair().publicKey;

      const { accountContract, signers } = await deployMultisig1_1();
      await accountContract.is_signer_guid(intoGuid(signers[0])).should.eventually.be.true;
      await accountContract.is_signer_guid(newSigner1).should.eventually.be.false;

      await accountContract.add_signers(CallData.compile([1, [starknetSigner(newSigner1)]]));
      await accountContract.is_signer_guid(newSigner1).should.eventually.be.true;

      const new_threshold = 2;

      const { transaction_hash } = await accountContract.add_signers(
        CallData.compile([new_threshold, [starknetSigner(newSigner2), starknetSigner(newSigner3)]]),
      );

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "ThresholdUpdated",
        data: CallData.compile([new_threshold]),
      });

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerAdded",
        additionalKeys: [newSigner2.toString()],
      });
      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerAdded",
        additionalKeys: [newSigner3.toString()],
      });
      await accountContract.is_signer_guid(newSigner2).should.eventually.be.true;
      await accountContract.is_signer_guid(newSigner3).should.eventually.be.true;
      await accountContract.get_threshold().should.eventually.equal(BigInt(new_threshold));
    });
    describe("Test all possible revert errors when adding signers", function () {
      it("Expect 'argent/already-a-signer' if adding an owner already in the list", async function () {
        const { accountContract, signers, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/already-a-signer", () =>
          accountContract.add_signers(CallData.compile([threshold, [signers[1]]])),
        );
      });

      it("Expect 'argent/already-a-signer' if adding the same owner twice", async function () {
        const { accountContract, threshold } = await deployMultisig1_3();

        const newSigner1 = starknetSigner(randomKeyPair().publicKey);

        await expectRevertWithErrorMessage("argent/already-a-signer", () =>
          accountContract.add_signers(CallData.compile([threshold, [newSigner1, newSigner1]])),
        );
      });

      it("Expect 'argent/invalid-signer-guid' when adding a zero signer", async function () {
        const { accountContract, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/invalid-signer-guid", () =>
          accountContract.add_signers(CallData.compile([threshold, [starknetSigner(0n)]])),
        );
      });

      it("Expect 'bad/invalid-threshold' if changing to a zero threshold", async function () {
        const { accountContract } = await deployMultisig1_3();

        const newSigner1 = starknetSigner(randomKeyPair().publicKey);
        await expectRevertWithErrorMessage("argent/invalid-threshold", () =>
          accountContract.add_signers(CallData.compile([0, [newSigner1]])),
        );
      });

      it("Expect 'bad/invalid-threshold' if threshold > no. owners", async function () {
        const { accountContract, signers } = await deployMultisig1_3();

        const newSigner1 = starknetSigner(randomKeyPair().publicKey);

        await expectRevertWithErrorMessage("argent/bad-threshold", () =>
          accountContract.add_signers(CallData.compile([signers.length + 2, [newSigner1]])),
        );
      });
    });
  });

  describe("remove_signers(new_threshold, signers_to_remove)", function () {
    const signersToRemove = [[0], [1], [2], [0, 1], [1, 0], [0, 2], [2, 0], [1, 2], [2, 1]];
    it("Should remove first signer and update threshold", async function () {
      const { accountContract, signers } = await deployMultisig1_3();

      const newThreshold = 2n;

      const { transaction_hash } = await accountContract.remove_signers(CallData.compile([newThreshold, [signers[0]]]));

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "ThresholdUpdated",
        data: CallData.compile([newThreshold]),
      });

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerRemoved",
        additionalKeys: [intoGuid(signers[0])],
      });

      await accountContract.is_signer_guid(intoGuid(signers[0])).should.eventually.be.false;
      await accountContract.get_threshold().should.eventually.equal(newThreshold);
    });

    signersToRemove.forEach((testCase) => {
      const indicesToRemove = testCase.join(", ");
      it(`Removing at index(es): ${indicesToRemove}`, async function () {
        const { accountContract, signers, threshold } = await deployMultisig1_3();

        await accountContract.remove_signers(CallData.compile([threshold, testCase.map((index) => signers[index])]));

        testCase.forEach(async (signerIndex) => {
          await accountContract.is_signer_guid(intoGuid(signers[signerIndex])).should.eventually.be.false;
        });

        const remainingSigners = signers.filter((_, index) => !testCase.includes(index)).map(Number);
        remainingSigners.forEach(async (signerIndex) => {
          await accountContract.is_signer_guid(intoGuid(signers[signerIndex])).should.eventually.be.true;
        });

        await accountContract.get_threshold().should.eventually.equal(threshold);
      });
    });

    describe("Test all possible revert errors when removing signers", function () {
      it("Expect 'argent/not-a-signer' when replacing an owner not in the list", async function () {
        const nonSigner = starknetSigner(randomKeyPair().publicKey);

        const { accountContract, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/not-a-signer", () =>
          accountContract.remove_signers(CallData.compile([threshold, [nonSigner]])),
        );
      });

      it("Expect 'argent/invalid-signer-guid' when removing a 0 signer", async function () {
        const { accountContract, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/invalid-signer-guid", () =>
          accountContract.remove_signers(CallData.compile([threshold, [starknetSigner(0n)]])),
        );
      });

      it("Expect 'argent/not-a-signer' removing the same owner twice in the same call", async function () {
        const { accountContract, signers, threshold } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/not-a-signer", () =>
          accountContract.remove_signers(CallData.compile([threshold, [signers[0], signers[0]]])),
        );
      });

      it("Expect argent/bad-threshold if threshold > no.of owners", async function () {
        const { accountContract, signers } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/bad-threshold", () =>
          accountContract.remove_signers(CallData.compile([3, [signers[1]]])),
        );
      });

      it("Expect argent/invalid-threshold when changing to a zero threshold ", async function () {
        const { accountContract, signers } = await deployMultisig1_3();

        await expectRevertWithErrorMessage("argent/invalid-threshold", () =>
          accountContract.remove_signers(CallData.compile([0, [signers[1]]])),
        );
      });
    });
  });
  describe("replace_signers(signer_to_remove, signer_to_add)", function () {
    it("Should replace one signer", async function () {
      const newSigner = starknetSigner(randomKeyPair().publicKey);

      const { accountContract, signers } = await deployMultisig1_1();

      const { transaction_hash } = await accountContract.replace_signer(CallData.compile([signers[0], newSigner]));

      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerRemoved",
        additionalKeys: [intoGuid(signers[0])],
      });
      await expectEvent(transaction_hash, {
        from_address: accountContract.address,
        eventName: "OwnerAdded",
        additionalKeys: [intoGuid(newSigner)],
      });
      await accountContract.is_signer_guid(intoGuid(newSigner)).should.eventually.be.true;
    });

    it("Should replace first signer", async function () {
      const newSigner = starknetSigner(randomKeyPair().publicKey);

      const { accountContract, signers } = await deployMultisig1_3();

      await accountContract.replace_signer(CallData.compile([signers[0], newSigner]));

      const signersList = await accountContract.get_signer_guids();
      expect(signersList).to.have.ordered.members([intoGuid(newSigner), intoGuid(signers[1]), intoGuid(signers[2])]);
    });

    it("Should replace middle signer", async function () {
      const newSigner = starknetSigner(randomKeyPair().publicKey);

      const { accountContract, signers } = await deployMultisig1_3();

      await accountContract.replace_signer(CallData.compile([signers[1], newSigner]));

      const signersList = await accountContract.get_signer_guids();
      expect(signersList).to.have.ordered.members([intoGuid(signers[0]), intoGuid(newSigner), intoGuid(signers[2])]);
    });

    it("Should replace last signer", async function () {
      const newSigner = starknetSigner(randomKeyPair().publicKey);

      const { accountContract, signers } = await deployMultisig1_3();

      await accountContract.replace_signer(CallData.compile([signers[2], newSigner]));

      const signersList = await accountContract.get_signer_guids();
      expect(signersList).to.have.ordered.members([intoGuid(signers[0]), intoGuid(signers[1]), intoGuid(newSigner)]);
    });
  });
  describe("Expect revert messages under different conditions when trying to replace an owner", function () {
    it("Expect 'argent/not-a-signer' when trying to replace a signer that isn't in the list", async function () {
      const nonSigner = starknetSigner(randomKeyPair().publicKey);
      const newSigner = starknetSigner(randomKeyPair().publicKey);

      const { accountContract } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.replace_signer(CallData.compile([nonSigner, newSigner])),
      );
    });
    it("Expect 'argent/already-a-signer' when replacing an owner with one already in the list", async function () {
      const { accountContract, signers } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/already-a-signer", () =>
        accountContract.replace_signer(CallData.compile([signers[0], signers[1]])),
      );
    });
    it("Expect 'argent/already-a-signer' when replacing an owner with themselves", async function () {
      const { accountContract, signers } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/already-a-signer", () =>
        accountContract.replace_signer(CallData.compile([signers[0], signers[0]])),
      );
    });
    it("Expect 'argent/invalid-signer-guid' when replacing an owner with a zero signer", async function () {
      const { accountContract, signers } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/invalid-signer-guid", () =>
        accountContract.replace_signer(CallData.compile([signers[0], starknetSigner(0n)])),
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
      const { accountContract, signers } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/bad-threshold", () =>
        accountContract.change_threshold(signers.length + 1),
      );
    });
    it("Expect 'argent/invalid-threshold' if threshold set to 0", async function () {
      const { accountContract } = await deployMultisig1_3();

      await expectRevertWithErrorMessage("argent/invalid-threshold", () => accountContract.change_threshold(0));
    });
  });
});
