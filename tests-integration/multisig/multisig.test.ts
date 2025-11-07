import { CallData, shortString, TransactionReceipt } from "starknet";
import {
  deployMultisig,
  deployMultisig1_1,
  expectEvent,
  expectExecutionRevert,
  expectRevertWithErrorMessage,
  randomStarknetKeyPair,
} from "../../lib";

describe("ArgentMultisig", function () {
  it(`Should deploy multisig contract`, async function () {
    const { accountContract, keys, receipt, threshold } = await deployMultisig({
      threshold: 1,
      signersLength: 2,
      selfDeploy: true,
    });

    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "ThresholdUpdated",
      data: CallData.compile([threshold]),
    });

    for (const key of keys) {
      await expectEvent(receipt, {
        from_address: accountContract.address,
        eventName: "OwnerAddedGuid",
        keys: [key.guid.toString()],
      });
    }

    await accountContract.get_threshold().should.eventually.equal(1n);
    await accountContract.get_name().should.eventually.equal(BigInt(shortString.encodeShortString("ArgentMultisig")));
    await accountContract.get_version().should.eventually.deep.equal({ major: 0n, minor: 5n, patch: 0n });
    await accountContract.is_signer_guid(keys[0].guid).should.eventually.be.true;
    await accountContract.is_signer_guid(keys[1].guid).should.eventually.be.true;
    await accountContract.is_signer_guid(0).should.eventually.be.false;
    await accountContract.is_signer_guid(randomStarknetKeyPair().publicKey).should.eventually.be.false;

    await expectRevertWithErrorMessage("argent/non-null-caller", accountContract.__validate__([]));
  });

  it("Should fail to deploy with invalid signatures", async function () {
    await expectRevertWithErrorMessage(
      "argent/signature-invalid-length",
      deployMultisig({
        threshold: 1,
        signersLength: 2,
        selfDeploy: true,
        selfDeploymentIndexes: [],
      }).then(({ receipt }) => receipt as TransactionReceipt),
    );

    await expectRevertWithErrorMessage(
      "argent/signature-invalid-length",
      deployMultisig({
        threshold: 1,
        signersLength: 2,
        selfDeploy: true,
        selfDeploymentIndexes: [0, 1],
      }).then(({ receipt }) => receipt as TransactionReceipt),
    );
  });

  it("Block deployment data", async function () {
    const { account } = await deployMultisig1_1();
    await expectExecutionRevert(
      "argent/invalid-deployment-data",
      account.execute([], {
        accountDeploymentData: ["0x1"],
      }),
    );
  });
});
