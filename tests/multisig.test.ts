import { CallData, shortString } from "starknet";
import { declareContract, expectEvent, expectRevertWithErrorMessage, randomKeyPair } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisig", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisig");
  });

  it("Should deploy multisig contract", async function () {
    const threshold = 1;
    const signersLength = 2;

    const { IAccount, signers, receipt } = await deployMultisig(
      multisigAccountClassHash,
      threshold,
      signersLength,
    );

    await expectEvent(receipt, {
      from_address: IAccount.address,
      keys: ["ConfigurationUpdated"],
      data: CallData.compile([threshold, signersLength, signers, []]),
    });

    await IAccount.get_threshold().should.eventually.equal(1n);
    await IAccount.get_signers().should.eventually.deep.equal(signers);
    await IAccount.get_name().should.eventually.equal(BigInt(shortString.encodeShortString("ArgentMultisig")));
    await IAccount.get_version().should.eventually.deep.equal({ major: 0n, minor: 1n, patch: 0n });

    await IAccount.is_signer(signers[0]).should.eventually.be.true;
    await IAccount.is_signer(signers[1]).should.eventually.be.true;
    await IAccount.is_signer(0).should.eventually.be.false;
    await IAccount.is_signer(randomKeyPair().publicKey).should.eventually.be.false;

    await expectRevertWithErrorMessage("argent/non-null-caller", () => IAccount.__validate__([]));
  });

  it("Should fail to deploy with invalid signatures", async function () {
    const threshold = 1;
    const signersLength = 2;

    await expectRevertWithErrorMessage("argent/invalid-signature-length", async () => {
      const { receipt } = await deployMultisig(multisigAccountClassHash, threshold, signersLength, []);
      return receipt;
    });

    await expectRevertWithErrorMessage("argent/invalid-signature-length", async () => {
      const { receipt } = await deployMultisig(multisigAccountClassHash, threshold, signersLength, [0, 1]);
      return receipt;
    });
  });
});
