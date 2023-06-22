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

      const newSigner1 = BigInt(randomKeyPair().publicKey);
      const newSigner2 = BigInt(randomKeyPair().publicKey);

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      const isSigner0 = await IAccount.is_signer(signers[0]);
      const isSigner1 = await IAccount.is_signer(newSigner1);
      expect(isSigner0).to.be.true;
      expect(isSigner1).to.be.false;

      await IAccount.add_signers(threshold, [newSigner1]);

      const isNewSigner1 = await IAccount.is_signer(newSigner1);
      expect(isNewSigner1).to.be.true;

      await IAccount.add_signers(threshold, [newSigner2]);

      const isSigner2 = await IAccount.is_signer(newSigner2);
      expect(isSigner2).to.be.true;
    });

    it("Expect 'argent/already-a-signer' when adding a new signer already in the linked list", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await expectRevertWithErrorMessage("argent/already-a-signer", () =>
        IAccount.add_signers(threshold, [signers[1]]),
      );
    });
  });

  describe("remove_signers(new_threshold, signers_to_remove)", function () {
    it("Should remove first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[0]]);

      const isSigner0 = await IAccount.is_signer(signers[0]);
      expect(isSigner0).to.be.false;
    });

    it("Should remove middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[1]]);

      const isSigner1 = await IAccount.is_signer(signers[1]);
      expect(isSigner1).to.be.false;
    });

    it("Should remove last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[2]]);

      const isSigner2 = await IAccount.is_signer(signers[2]);
      expect(isSigner2).to.be.false;
    });

    it("Should remove first and middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[0], signers[1]]);

      const isSigner0 = await IAccount.is_signer(signers[0]);
      expect(isSigner0).to.be.false;

      const isSigner1 = await IAccount.is_signer(signers[1]);
      expect(isSigner1).to.be.false;
    });

    it("Should remove first and last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[0], signers[2]]);

      const isSigner0 = await IAccount.is_signer(signers[0]);
      expect(isSigner0).to.be.false;

      const isSigner2 = await IAccount.is_signer(signers[2]);
      expect(isSigner2).to.be.false;
    });

    it("Should remove middle and last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[1], signers[2]]);

      const isSigner1 = await IAccount.is_signer(signers[1]);
      expect(isSigner1).to.be.false;

      const isSigner2 = await IAccount.is_signer(signers[2]);
      expect(isSigner2).to.be.false;
    });

    it("Should remove middle and first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[1], signers[0]]);

      const isSigner1 = await IAccount.is_signer(signers[1]);
      expect(isSigner1).to.be.false;

      const isSigner0 = await IAccount.is_signer(signers[0]);
      expect(isSigner0).to.be.false;
    });

    it("Should remove last and first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[2], signers[0]]);

      const isSigner2 = await IAccount.is_signer(signers[2]);
      expect(isSigner2).to.be.false;

      const isSigner0 = await IAccount.is_signer(signers[0]);
      expect(isSigner0).to.be.false;
    });

    it("Should remove last and middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.remove_signers(threshold, [signers[2], signers[1]]);

      const isSigner2 = await IAccount.is_signer(signers[2]);
      expect(isSigner2).to.be.false;

      const isSigner1 = await IAccount.is_signer(signers[1]);
      expect(isSigner1).to.be.false;
    });

    it("Expect 'argent/not-a-signer' when removing a non-existent signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const nonSigner = BigInt(randomKeyPair().publicKey);

      const { IAccount } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        IAccount.remove_signers(threshold, [nonSigner]),
      );
    });

    it("Expect 'argent/bad-threshold' when new threshold is invalid (< number of remaining signers)", async function () {
      const threshold = 1;
      const signersLength = 3;

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await expectRevertWithErrorMessage("argent/bad-threshold", () => IAccount.remove_signers(3, [signers[1]]));
    });
  });
  describe("replace_signers(signer_to_remove, signer_to_add)", function () {
    it("Should replace one signer", async function () {
      const threshold = 1;
      const signersLength = 1;

      const newSigner = BigInt(randomKeyPair().publicKey);

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.replace_signer(signers[0], newSigner);

      const isNewSigner = await IAccount.is_signer(newSigner);
      expect(isNewSigner).to.be.true;
    });

    it("Should replace first signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const newSigner = BigInt(randomKeyPair().publicKey);

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.replace_signer(signers[0], newSigner);

      const signersList = await IAccount.get_signers();
      expect(signersList).to.have.ordered.members([newSigner, signers[1], signers[2]]);
    });

    it("Should replace middle signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const newSigner = BigInt(randomKeyPair().publicKey);

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.replace_signer(signers[1], newSigner);

      const signersList = await IAccount.get_signers();
      expect(signersList).to.have.ordered.members([signers[0], newSigner, signers[2]]);
    });

    it("Should replace last signer", async function () {
      const threshold = 1;
      const signersLength = 3;

      const newSigner = BigInt(randomKeyPair().publicKey);

      const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      await IAccount.replace_signer(signers[2], newSigner);

      const signersList = await IAccount.get_signers();
      expect(signersList).to.have.ordered.members([signers[0], signers[1], newSigner]);
    });
  });

  it("Expect 'argent/not-a-signer' when replacing a non-existing signer", async function () {
    const threshold = 1;
    const signersLength = 3;

    const nonSigner = BigInt(randomKeyPair().publicKey);
    const newSigner = BigInt(randomKeyPair().publicKey);

    const { IAccount } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

    await expectRevertWithErrorMessage("argent/not-a-signer", () =>
      IAccount.replace_signer(nonSigner, newSigner),
    );
  });

  it("Expect 'argent/already-a-signer' when replacing a signer with an existing one", async function () {
    const threshold = 1;
    const signersLength = 3;

    const { IAccount, signers } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

    await expectRevertWithErrorMessage("argent/already-a-signer", () =>
      IAccount.replace_signer(signers[0], signers[1]),
    );
  });
});
