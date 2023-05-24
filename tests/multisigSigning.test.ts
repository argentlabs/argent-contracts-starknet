import { expect } from "chai";
import { ec } from "starknet";
import { declareContract, expectRevertWithErrorMessage, randomPrivateKey } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisig: signing", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisig");
  });

  describe("is_valid_signature(hash, signatures)", function () {
    it("Should verify that a multisig signer has signed a message", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = 424242;
      const ERC1271_VALIDATED = 0x1626ba7e;

      const { accountContract, signers, keys } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      const signerPrivateKey = keys[0].privateKey;
      const { r, s } = ec.starkCurve.sign(messageHash.toString(16), signerPrivateKey);

      const validSignature = await accountContract.is_valid_signature(BigInt(messageHash), [signers[0], r, s]);

      expect(validSignature).to.equal(BigInt(ERC1271_VALIDATED));
    });

    it("Expect 'argent/not-a-signer' when a non-signer signs a message", async function () {
      const threshold = 1;
      const signersLength = 1;
      const messageHash = 424242;

      const { accountContract } = await deployMultisig(multisigAccountClassHash, threshold, signersLength);
      const invalidPrivateKey = randomPrivateKey();
      const invalidSigner = BigInt(ec.starkCurve.getStarkKey(invalidPrivateKey));
      const { r, s } = ec.starkCurve.sign(messageHash.toString(16), invalidPrivateKey);

      await expectRevertWithErrorMessage("argent/not-a-signer", () =>
        accountContract.is_valid_signature(BigInt(messageHash), [invalidSigner, r, s]),
      );
    });
  });
});
