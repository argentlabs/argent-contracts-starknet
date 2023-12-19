import { expect } from "chai";
import { uint256 } from "starknet";
import { deployAccount, getEthContract, getEthBalance, expectRevertWithErrorMessage, fundAccount } from "./lib";

describe.only("ArgentAccount: TxV3", function () {

  it("Should be possible to send eth", async function () {
    const { account } = await deployAccount({ useTxV3: true });
    const ethContract = await getEthContract();
    const amount = 1n;
    await fundAccount(account.address, amount, "ETH");
    const recipient = "0x42";
    const recipientInitialBalance = await getEthBalance(recipient);
    ethContract.connect(account);
    const { transaction_hash: transferTxHash } = await ethContract.transfer(recipient, uint256.bnToUint256(amount));
    await account.waitForTransaction(transferTxHash);
    const senderFinalBalance = await getEthBalance(account.address);
    const recipientFinalBalance = await getEthBalance(recipient);
    expect(senderFinalBalance).to.equal(0n);
    expect(recipientFinalBalance).to.equal(recipientInitialBalance + amount);
  });

  it("Should reject paymaster data", async function () {
    const amount = 1n;
    const { account } = await deployAccount({ useTxV3: true });
    await fundAccount(account.address, amount, "ETH");
    const ethContract = await getEthContract();
    const call = ethContract.populateTransaction.transfer("0x42", uint256.bnToUint256(amount));
    await expectRevertWithErrorMessage("argent/unsupported-paymaster", () => {
      return account.execute(call, undefined, { paymasterData: ["0x1"] });
    });
  });
});
