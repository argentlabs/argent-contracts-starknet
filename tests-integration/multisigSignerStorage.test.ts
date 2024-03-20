import { CallData } from "starknet";
import { deployMultisig1_3, expectRevertWithErrorMessage, zeroStarknetSignatureType } from "./lib";

describe("ArgentMultisig: signer storage", function () {
  it("Expect deserialization error when adding a zero signer", async function () {
    const { accountContract, threshold } = await deployMultisig1_3();
    await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
      accountContract.add_signers(CallData.compile([threshold, [zeroStarknetSignatureType()]])),
    );
  });

  it("Expect deserialization error when replacing an owner with a zero signer", async function () {
    const { accountContract, threshold } = await deployMultisig1_3();
    await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
      accountContract.replace_signer(CallData.compile([threshold, zeroStarknetSignatureType()])),
    );
  });

  describe("remove_signers(new_threshold, signers_to_remove)", function () {
    it("Expect deserialization error when removing a 0 signer", async function () {
      const { accountContract, threshold } = await deployMultisig1_3();
      await expectRevertWithErrorMessage("Failed to deserialize param #2", () =>
        accountContract.remove_signers(CallData.compile([threshold, [zeroStarknetSignatureType()]])),
      );
    });

    const signersToRemove = [[0], [1], [2], [0, 2]];

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
  });
});
