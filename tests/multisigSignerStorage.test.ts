import { expect } from "chai";
import { declareContract, expectRevertWithErrorMessage, randomKeyPair } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisig: signer storage", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisig");
  });

  describe("add_signers(new_threshold, signers_to_add)", function () {
    it("Should add one new signer", async function () {
      const threshold = 1;
      const signersLength = 1;

      const newSigner1 = randomKeyPair().publicKey;
      const newSigner2 = randomKeyPair().publicKey;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      const isSigner0 = await accountContract.is_signer(signers[0]);
      const isSigner1 = await accountContract.is_signer(newSigner1);
      expect(isSigner0).to.be.true;
      expect(isSigner1).to.be.false;

      await accountContract.add_signers(threshold, [newSigner1]);

      const isNewSigner1 = await accountContract.is_signer(newSigner1);
      expect(isNewSigner1).to.be.true;

      await accountContract.add_signers(threshold, [newSigner2]);

      const isSigner2 = await accountContract.is_signer(newSigner2);
      expect(isSigner2).to.be.true;
    });

    it("Expect 'argent/already-a-signer' when adding a new signer already in the linked list", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await expectRevertWithErrorMessage("argent/already-a-signer", () =>
        accountContract.add_signers(threshold, [signers[1]]),
      );
    });
  });

  describe("remove_signers(new_threshold, signers_to_remove)", function () {
    it("Should remove first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[0]]);

      const isSigner0 = await accountContract.is_signer(signers[0]);
      expect(isSigner0).to.be.false;
    });

    it("Should remove middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[1]]);

      const isSigner1 = await accountContract.is_signer(signers[1]);
      expect(isSigner1).to.be.false;
    });

    it("Should remove last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[2]]);

      const isSigner2 = await accountContract.is_signer(signers[2]);
      expect(isSigner2).to.be.false;
    });

    it("Should remove first and middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[0], signers[1]]);

      const isSigner0 = await accountContract.is_signer(signers[0]);
      expect(isSigner0).to.be.false;

      const isSigner1 = await accountContract.is_signer(signers[1]);
      expect(isSigner1).to.be.false;
    });

    it("Should remove first and last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[0], signers[2]]);

      const isSigner0 = await accountContract.is_signer(signers[0]);
      expect(isSigner0).to.be.false;

      const isSigner2 = await accountContract.is_signer(signers[2]);
      expect(isSigner2).to.be.false;
    });

    it("Should remove middle and last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[1], signers[2]]);

      const isSigner1 = await accountContract.is_signer(signers[1]);
      expect(isSigner1).to.be.false;

      const isSigner2 = await accountContract.is_signer(signers[2]);
      expect(isSigner2).to.be.false;
    });

    it("Should remove middle and first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[1], signers[0]]);

      const isSigner1 = await accountContract.is_signer(signers[1]);
      expect(isSigner1).to.be.false;

      const isSigner0 = await accountContract.is_signer(signers[0]);
      expect(isSigner0).to.be.false;
    });

    it("Should remove last and first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[2], signers[0]]);

      const isSigner2 = await accountContract.is_signer(signers[2]);
      expect(isSigner2).to.be.false;

      const isSigner0 = await accountContract.is_signer(signers[0]);
      expect(isSigner0).to.be.false;
    });

    it("Should remove last and middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.remove_signers(threshold, [signers[2], signers[1]]);

      const isSigner2 = await accountContract.is_signer(signers[2]);
      expect(isSigner2).to.be.false;

      const isSigner1 = await accountContract.is_signer(signers[1]);
      expect(isSigner1).to.be.false;
    });

    it("Expect 'argent/not-a-signer' when removing a non-existent signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const nonSigner = randomKeyPair().publicKey;

      const { accountContract } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.remove_signers(threshold, [nonSigner]),
      );
    });

    it("Expect 'argent/bad-threshold' when new threshold is invalid (< number of remaining signers)", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await expectRevertWithErrorMessage("argent/bad-threshold", () => accountContract.remove_signers(3, [signers[1]]));
    });
  });
  describe("replace_signers(signer_to_remove, signer_to_add)", function () {
    it("Should replace one signer", async function () {
      const threshold = 1;
      const signersLength = 1;

      const newSigner = randomKeyPair().publicKey;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.replace_signer(signers[0], newSigner);

      const isNewSigner = await accountContract.is_signer(newSigner);
      expect(isNewSigner).to.be.true;
    });

    it("Should replace first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const newSigner = randomKeyPair().publicKey;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.replace_signer(signers[0], newSigner);

      const signersList = await accountContract.get_signers();
      expect(signersList).to.have.ordered.members([newSigner, signers[1], signers[2]]);
    });

    it("Should replace middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const newSigner = randomKeyPair().publicKey;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.replace_signer(signers[1], newSigner);

      const signersList = await accountContract.get_signers();
      expect(signersList).to.have.ordered.members([signers[0], newSigner, signers[2]]);
    });

    it("Should replace last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const newSigner = randomKeyPair().publicKey;

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await accountContract.replace_signer(signers[2], newSigner);

      const signersList = await accountContract.get_signers();
      expect(signersList).to.have.ordered.members([signers[0], signers[1], newSigner]);
    });
  });

  it("Expect 'argent/not-a-signer' when replacing a non-existing signer", async function () {
    const threshold = 1;
    const signersLength = 3;

    const nonSigner = randomKeyPair().publicKey;
    const newSigner = randomKeyPair().publicKey;

    const { accountContract } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

    await expectRevertWithErrorMessage("argent/not-a-signer", () =>
      accountContract.replace_signer(nonSigner, newSigner),
    );
  });

  it("Expect 'argent/already-a-signer' when replacing a signer with an existing one", async function () {
    const threshold = 1;
    const signersLength = 3;

    const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

    await expectRevertWithErrorMessage("argent/already-a-signer", () =>
      accountContract.replace_signer(signers[0], signers[1]),
    );
  });
});
