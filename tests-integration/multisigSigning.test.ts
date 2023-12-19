import { expect } from "chai";
import { num, shortString } from "starknet";
import { expectRevertWithErrorMessage, randomKeyPair, restartDevnetIfTooLong } from "./lib";
import { deployMultisig, deployMultisig1_1 } from "./lib/multisig";

describe("ArgentMultisig: signing", function () {
  before(async () => {
    await restartDevnetIfTooLong();
  });

  const VALID = BigInt(shortString.encodeShortString("VALID"));

  describe("is_valid_signature(hash, signatures)", function () {
    it("Should verify that a multisig owner has signed a message", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, signers, keys } = await deployMultisig1_1();

      const [r, s] = keys[0].signHash(messageHash);

      const validSignatureResult = await accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r, s]);

      expect(validSignatureResult).to.equal(VALID);
    });

    it("Should verify numerous multisig owners have signed a message", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, signers, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const [r1, s1] = keys[0].signHash(messageHash);
      const [r2, s2] = keys[1].signHash(messageHash);

      const validSignatureResult = await accountContract.is_valid_signature(BigInt(messageHash), [
        signers[0],
        r1,
        s1,
        signers[1],
        r2,
        s2,
      ]);

      expect(validSignatureResult).to.equal(VALID);
    });

    it("Should verify that signatures are in the correct order", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, signers, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const [r1, s1] = keys[0].signHash(messageHash);
      const [r2, s2] = keys[1].signHash(messageHash);

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [signers[1], r2, s2, signers[0], r1, s1]),
      );
    });

    it("Should verify that signatures are in the not repeated", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, signers, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const [r, s] = keys[0].signHash(messageHash);

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r, s, signers[0], r, s]),
      );
    });

    it("Expect 'argent/invalid-signature-length' when an owner's signature is missing", async function () {
      const messageHash = num.toHex(424242);
      const { accountContract, signers, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const [r, s] = keys[0].signHash(messageHash);

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r, s]),
      );
    });

    it("Expect 'argent/not-a-signer' when a non-owner signs a message", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract } = await deployMultisig1_1();
      const invalid = randomKeyPair();
      const [r, s] = invalid.signHash(messageHash);

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [invalid.publicKey, r, s]),
      );
    });

    it("Expect 'argent/invalid-signature-length' when the signature is improperly formatted/empty", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, keys, signers } = await deployMultisig1_1();

      const [r] = keys[0].signHash(messageHash);

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r]),
      );

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), []),
      );
    });
  });
});
