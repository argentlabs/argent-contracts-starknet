import { Contract } from "starknet";
import { deployAccount, expectRevertWithErrorMessage, deployMultisig1_1, deployContract } from "./lib";

for (const accountType of ["individual", "multisig"]) {
  describe(`TxV3 ${accountType} account`, function () {
    let MockDapp: Contract;

    before(async () => {
      MockDapp = await deployContract("MockDapp");
    });

    async function deployAccountType() {
      if (accountType === "individual") {
        return await deployAccount({ useTxV3: true });
      } else if (accountType === "multisig") {
        return await deployMultisig1_1({ useTxV3: true });
      } else {
        throw new Error(`Unknown account type ${accountType}`);
      }
    }

    it("Should be possible to call dapp", async function () {
      const { account } = await deployAccountType();
      MockDapp.connect(account);
      const { transaction_hash: transferTxHash } = await MockDapp.set_number(42n);
      await account.waitForTransaction(transferTxHash);
      await MockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    });

    it("Should reject paymaster data", async function () {
      const { account } = await deployAccountType();
      MockDapp.connect(account);
      const call = MockDapp.populateTransaction.set_number(42n);
      await expectRevertWithErrorMessage("argent/unsupported-paymaster", () => {
        return account.execute(call, undefined, { paymasterData: ["0x1"] });
      });
    });
  });
}
