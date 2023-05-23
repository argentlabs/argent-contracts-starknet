import { CallData, shortString } from "starknet";
import { declareContract, expectEvent } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisigAccount", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisigAccount");
  });

  describe("Initialization", function () {
    it("Should deploy multisig contract", async function () {
      const threshold = 1;
      const signersLength = 2;

      const { accountContract, signers, receipt } = await deployMultisig(
        multisigAccountClassHash,
        threshold,
        signersLength,
      );

      await expectEvent(receipt, {
        from_address: accountContract.address,
        keys: ["ConfigurationUpdated"],
        data: CallData.compile([threshold, signersLength, signers, []]),
      });

      await accountContract.get_threshold().should.eventually.equal(1n);
      await accountContract.get_signers().should.eventually.deep.equal(signers);
      await accountContract.get_name().should.eventually.equal(BigInt(shortString.encodeShortString("ArgentMultisig")));
      await accountContract.get_version().should.eventually.deep.equal({ major: 0n, minor: 1n, patch: 0n });
    });
  });
});
