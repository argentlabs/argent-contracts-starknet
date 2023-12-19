import { expect } from "chai";
import { Contract, num, uint256 } from "starknet";
import {
  declareContract,
  deployAccount,
  deployer,
  ensureAccepted,
  expectEvent,
  expectRevertWithErrorMessage,
  getEthContract,
  loadContract,
  restartDevnetIfTooLong,
  getEthBalance,
  fundAccount,
} from "./lib";

describe("ArgentAccount: TxV3", function () {
  let testDappContract: Contract;
  let ethContract: Contract;

  before(async () => {
    await restartDevnetIfTooLong();
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
    testDappContract = await loadContract(contract_address);
    ethContract = await getEthContract();
  });

  it("Should be possible to send eth", async function () {
    const { account } = await deployAccount({ useTxV3: true });
    const amount = 10n;
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
});
