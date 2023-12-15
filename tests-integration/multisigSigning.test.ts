import { expect } from "chai";
import { num, shortString } from "starknet";
import { declareContract, expectRevertWithErrorMessage, randomKeyPair } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisig: signing", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisig");
  });
  const VALID = BigInt(shortString.encodeShortString("VALID"));

  describe("is_valid_signature(hash, signatures)", function () {
    it("Should verify that a multisig owner has signed a message", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      let signatures = ["1"];
      signatures = signatures.concat(keys[0].signHash(messageHash));

      const validSignatureResult = await accountContract.is_valid_signature(BigInt(messageHash), signatures);

      expect(validSignatureResult).to.equal(VALID);
    });

    it("Should verify numerous multisig owners have signed a message", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      let signatures = ["2"];
      signatures = signatures.concat(keys[0].signHash(messageHash));
      signatures = signatures.concat(keys[1].signHash(messageHash));

      const validSignatureResult = await accountContract.is_valid_signature(BigInt(messageHash), signatures);

      expect(validSignatureResult).to.equal(VALID);
    });

    it("Should verify that signatures are in the correct order", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      let signatures = ["2"];
      signatures = signatures.concat(keys[1].signHash(messageHash));
      signatures = signatures.concat(keys[0].signHash(messageHash));

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Should verify that signatures are in the not repeated", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      let signatures = ["2"];
      signatures = signatures.concat(keys[0].signHash(messageHash));
      signatures = signatures.concat(keys[0].signHash(messageHash));

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Expect 'argent/invalid-signature-length' when an owner's signature is missing", async function () {
      const threshold = 2;
      const signersLength = 2;
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);

      let signatures = ["1"];
      signatures = signatures.concat(keys[0].signHash(messageHash));

      await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Expect 'argent/not-a-signer' when a non-owner signs a message", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = num.toHex(424242);

      const { accountContract } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);
      const invalid = randomKeyPair();
      let signatures = ["1"];
      signatures = signatures.concat(invalid.signHash(messageHash));

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
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

      const [r] = keys[0].signHash(messageHash);

      await expectRevertWithErrorMessage("argent/undeserializable", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [1, 0, signers[0], r]),
      );

      await expectRevertWithErrorMessage("argent/undeserializable", () =>
        accountContract.is_valid_signature(BigInt(messageHash), []),
      );
    });
  });
});
