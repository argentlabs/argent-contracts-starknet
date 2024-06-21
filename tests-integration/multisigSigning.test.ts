import { expect } from "chai";
import { num } from "starknet";
import { MultisigSigner, expectRevertWithErrorMessage, randomStarknetKeyPair, sortByGuid } from "../lib";
import { VALID } from "../lib/accounts";
import { deployMultisig, deployMultisig1_1 } from "../lib/multisig";

describe("ArgentMultisig: signing", function () {
  describe("is_valid_signature(hash, signatures)", function () {
    it("Should verify that a multisig owner has signed a message", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig1_1();

      const signatures = await new MultisigSigner(keys).signRaw(messageHash);

      const validSignatureResult = await accountContract.is_valid_signature(BigInt(messageHash), signatures);

      expect(validSignatureResult).to.equal(VALID);
    });

    it("Should verify numerous multisig owners have signed a message", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const signatures = await new MultisigSigner(keys).signRaw(messageHash);

      const validSignatureResult = await accountContract.is_valid_signature(BigInt(messageHash), signatures);

      expect(validSignatureResult).to.equal(VALID);
    });

    it("Should verify that signatures are in the correct order", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const signatures = await new MultisigSigner(sortByGuid(keys).reverse()).signRaw(messageHash);

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Should verify that signatures are in the not repeated", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const signatures = await new MultisigSigner([keys[0], keys[0]]).signRaw(messageHash);

      await expectRevertWithErrorMessage("argent/signatures-not-sorted", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Expect 'argent/signature-invalid-length' when an owner's signature is missing", async function () {
      const messageHash = num.toHex(424242);
      const { accountContract, keys } = await deployMultisig({ threshold: 2, signersLength: 2 });

      const signatures = await new MultisigSigner([keys[0]]).signRaw(messageHash);

      await expectRevertWithErrorMessage("argent/signature-invalid-length", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Expect 'argent/not-a-signer' when a non-owner signs a message", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract } = await deployMultisig1_1();
      const invalid = randomStarknetKeyPair();
      const signatures = await new MultisigSigner([invalid]).signRaw(messageHash);

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.is_valid_signature(BigInt(messageHash), signatures),
      );
    });

    it("Expect 'argent/undeserializable' when the signature is improperly formatted/empty", async function () {
      const messageHash = num.toHex(424242);

      const { accountContract, keys } = await deployMultisig1_1();

      const [publicKey, r] = await keys[0].signRaw(messageHash);

      await expectRevertWithErrorMessage("argent/invalid-signature-format", () =>
        // Missing S argument
        accountContract.is_valid_signature(BigInt(messageHash), [1, 0, publicKey, r]),
      );

      // No SignerSignature
      await expectRevertWithErrorMessage("argent/invalid-signature-format", () =>
        accountContract.is_valid_signature(BigInt(messageHash), []),
      );
    });
  });
});
