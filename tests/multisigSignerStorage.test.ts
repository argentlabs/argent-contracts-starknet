import { CallData, shortString } from "starknet";
import { declareContract, expectEvent } from "./lib";
import { deployMultisig} from "./lib/multisig";
import { expect } from "chai";


describe("ArgentMultisig: signer storage", function () {

  let multisigAccountClassHash: string;

    before(async () => {
        multisigAccountClassHash = await declareContract("ArgentMultisigAccount");
      });

      describe("add_signers(new_threshold, signers_to_add)", function () {
        it("Should add one new signer and update threshold", async function () {
            const threshold = 1;
            const signersLength = 1;
      
            const { accountContract, signers, receipt } = await deployMultisig(
              multisigAccountClassHash,
              threshold,
              signersLength,
            );
            const is_signer = await accountContract.is_signer(signers[0]);
            expect(is_signer).to.be.true;
            
        });
    });
    

});