import { declareContract, randomPrivateKeys } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisigAccount", function () {
  let multisigAccountClassHash: string;

  before(async () => {
    multisigAccountClassHash = await declareContract("ArgentMultisigAccount");
  });

  describe("Initialization", function () {
    it("Should deploy multisig contract", async function () {
      const threshold = 1;
      const privateKeys = randomPrivateKeys(2);

      const { accountContract, signers } = await deployMultisig(multisigAccountClassHash, threshold, privateKeys);

      await accountContract.get_threshold().should.eventually.equal(1n);
      await accountContract.get_signers().should.eventually.deep.equal(signers);
    });
  });
});
