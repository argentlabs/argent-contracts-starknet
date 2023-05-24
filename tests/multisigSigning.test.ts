import { expect } from "chai";
import { ec, num} from "starknet";
import { declareContract, expectRevertWithErrorMessage, randomPrivateKey } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisig: signing", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisig");
  });

  describe("is_valid_signature(hash, signatures)", function () {
    it("Should verify that a multisig owner has signed a message", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = num.toHex(424242);
      const ERC1271_VALIDATED = 0x1626ba7e;

      const { accountContract, signers, keys } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      const signerPrivateKey = keys[0].privateKey;
      const { r, s } = ec.starkCurve.sign(messageHash, signerPrivateKey);

      const validSignature = await accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r, s]);

      expect(validSignature).to.equal(BigInt(ERC1271_VALIDATED));
    });

    it("Should verify numerous multisig owners have signed a message and signatures are in the correct order/not repeated", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);
      const ERC1271_VALIDATED = 0x1626ba7e;

      const { accountContract, signers, keys } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      const signerPrivateKey1 = keys[0].privateKey;
      const signature1 = ec.starkCurve.sign(messageHash, signerPrivateKey1);

      const signerPrivateKey2 = keys[1].privateKey;
      const signature2 = ec.starkCurve.sign(messageHash, signerPrivateKey2);

      const validSignature = await accountContract.is_valid_signature(BigInt(messageHash), [
        signers[0],
        signature1.r,
        signature1.s,
        signers[1],
        signature2.r,
        signature2.s,
      ]);

      expect(validSignature).to.equal(BigInt(ERC1271_VALIDATED));
    });

    it("Should verify that signatures are in the correct order/not repeated", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);

      const { accountContract, signers, keys } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      const signerPrivateKey1 = keys[0].privateKey;
      const signature1 = ec.starkCurve.sign(messageHash, signerPrivateKey1);

      const signerPrivateKey2 = keys[1].privateKey;
      const signature2 = ec.starkCurve.sign(messageHash, signerPrivateKey2);

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [
          signers[1],
          signature2.r,
          signature2.s,
          signers[0],
          signature1.r,
          signature1.s,
        ]),
      );

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [
          signers[0],
          signature1.r,
          signature1.s,
          signers[0],
          signature1.r,
          signature1.s,
        ]),
      );
    });

    it("Expect 'argent/invalid-signature-length' when an owner's signature is missing", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);

      const { accountContract, signers, keys } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      const signerPrivateKey1 = keys[0].privateKey;
      const signature1 = ec.starkCurve.sign(messageHash, signerPrivateKey1);

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [signers[0], signature1.r, signature1.s]),
      );
    });

    it("Expect 'argent/not-a-signer' when a non-owner signs a message", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = num.toHex(424242);

      const { accountContract } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);
      const invalidPrivateKey = randomPrivateKey();
      const invalidSigner = BigInt(ec.starkCurve.getStarkKey(invalidPrivateKey));
      const { r, s } = ec.starkCurve.sign(messageHash, invalidPrivateKey);

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [invalidSigner, r, s]),
      );
    });

    it("Expect 'argent/invalid-signature-length' when the signature is improperly formatted/empty", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = num.toHex(424242);

      const { accountContract, keys, signers } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      const signerPrivateKey = keys[0].privateKey;
      const { r, s } = ec.starkCurve.sign(messageHash, signerPrivateKey);

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r]),
      );

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), []),
      );
    });
  });
});
