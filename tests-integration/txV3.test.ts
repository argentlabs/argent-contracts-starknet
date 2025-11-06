import { Contract } from "starknet";
import { deployAccount, deployMultisig1_1, expectRevertWithErrorMessage, generateRandomNumber, manager } from "../lib";

for (const accountType of ["individual", "multisig"]) {
  describe(`TxV3 ${accountType} account`, function () {
    let mockDapp: Contract;

    before(async () => {
      mockDapp = await manager.declareAndDeployContract("MockDapp");
    });

    async function deployAccountType() {
      if (accountType === "individual") {
        return await deployAccount();
      } else if (accountType === "multisig") {
        return await deployMultisig1_1();
      } else {
        throw new Error(`Unknown account type ${accountType}`);
      }
    }

    it("Should be possible to call dapp", async function () {
      const { account } = await deployAccountType();
      mockDapp.providerOrAccount = account;
      const randomNumber = generateRandomNumber();
      const { transaction_hash: transferTxHash } = await mockDapp.set_number(randomNumber);
      await account.waitForTransaction(transferTxHash);
      await mockDapp.get_number(account.address).should.eventually.equal(randomNumber, "invalid new value");
    });

    it("Should reject paymaster data", async function () {
      const { account } = await deployAccountType();
      mockDapp.providerOrAccount = account;
      const call = mockDapp.populateTransaction.set_number(generateRandomNumber());
      await expectRevertWithErrorMessage(
        "argent/unsupported-paymaster",
        account.execute(call, {
          paymasterData: ["0x1"],
        }),
      );
    });
  });
}
