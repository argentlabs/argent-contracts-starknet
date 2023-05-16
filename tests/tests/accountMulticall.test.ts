import { expect } from "chai";
import { Contract, uint256 } from "starknet";
import {
  declareContract,
  deployAccount,
  deployerAccount,
  expectRevertWithErrorMessage,
  getEthContract,
  loadContract,
} from "./shared";

describe("ArgentAccount: multicall", function () {
  let argentAccountClassHash: string;
  let testDappContract: Contract;
  let ethContract: Contract;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployerAccount.deployContract({
      classHash: testDappClassHash,
    });
    testDappContract = await loadContract(contract_address);
    ethContract = await getEthContract();
  });

  it("Should be possible to send eth with a Cairo1 account", async function () {
    const account = await deployAccount(argentAccountClassHash);
    const recipient = "0x42";
    const amount = uint256.bnToUint256(1000);
    const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
    const { balance: recipientInitialBalance } = await ethContract.balanceOf(recipient);
    ethContract.connect(account);
    // TODO it should be possible to do this at some point
    // await ethContract.transfer(recipient, amount);
    const { transaction_hash: transferTxHash } = await account.execute(
      ethContract.populateTransaction.transfer(recipient, amount),
    );

    await account.waitForTransaction(transferTxHash);
    const { balance: senderFinalBalance } = await ethContract.balanceOf(account.address);
    const { balance: recipientFinalBalance } = await ethContract.balanceOf(recipient);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(uint256.uint256ToBN(senderInitialBalance) + 1000n > uint256.uint256ToBN(senderFinalBalance)).to.be.true;
    expect(uint256.uint256ToBN(recipientInitialBalance) + 1000n).to.equal(uint256.uint256ToBN(recipientFinalBalance));
  });

  it("Should be possible to send eth with a Cairo1 account using a multicall", async function () {
    const account = await deployAccount(argentAccountClassHash);
    const recipient1 = "0x42";
    const amount1 = uint256.bnToUint256(1000);
    const recipient2 = "0x43";
    const amount2 = uint256.bnToUint256(42000);

    const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
    const { balance: recipient1InitialBalance } = await ethContract.balanceOf(recipient1);
    const { balance: recipient2InitialBalance } = await ethContract.balanceOf(recipient2);

    const { transaction_hash: transferTxHash } = await account.execute([
      ethContract.populateTransaction.transfer(recipient1, amount1),
      ethContract.populateTransaction.transfer(recipient2, amount2),
    ]);
    await account.waitForTransaction(transferTxHash);

    const { balance: senderFinalBalance } = await ethContract.balanceOf(account.address);
    const { balance: recipient1FinalBalance } = await ethContract.balanceOf(recipient1);
    const { balance: recipient2FinalBalance } = await ethContract.balanceOf(recipient2);
    expect(senderInitialBalance.high).to.equal(senderFinalBalance.high);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(Number(senderInitialBalance.low)).to.be.greaterThan(Number(senderFinalBalance.low) + 1000 + 42000);
    expect(uint256.uint256ToBN(recipient1InitialBalance) + 1000n).to.equal(uint256.uint256ToBN(recipient1FinalBalance));
    expect(uint256.uint256ToBN(recipient2InitialBalance) + 42000n).to.equal(
      uint256.uint256ToBN(recipient2FinalBalance),
    );
  });

  it("Should be possible to invoke different contracts in a multicall", async function () {
    const account = await deployAccount(argentAccountClassHash);
    const recipient1 = "0x42";
    const amount1 = uint256.bnToUint256(1000);

    const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
    const { balance: recipient1InitialBalance } = await ethContract.balanceOf(recipient1);
    const initalNumber = await testDappContract.get_number(account.address);
    expect(initalNumber).to.equal(0n);

    const { transaction_hash: transferTxHash } = await account.execute([
      ethContract.populateTransaction.transfer(recipient1, amount1),
      testDappContract.populateTransaction.set_number(42),
    ]);
    await account.waitForTransaction(transferTxHash);

    const { balance: senderFinalBalance } = await ethContract.balanceOf(account.address);
    const { balance: recipient1FinalBalance } = await ethContract.balanceOf(recipient1);
    const finalNumber = await testDappContract.get_number(account.address);
    expect(senderInitialBalance.high).to.equal(senderFinalBalance.high);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(Number(senderInitialBalance.low)).to.be.greaterThan(Number(senderFinalBalance.low) + 1000 + 42000);
    expect(uint256.uint256ToBN(recipient1InitialBalance) + 1000n).to.equal(uint256.uint256ToBN(recipient1FinalBalance));
    expect(finalNumber).to.equal(42n);
  });

  it("Should keep the tx in correct", async function () {
    const account = await deployAccount(argentAccountClassHash);

    const initalNumber = await testDappContract.get_number(account.address);
    expect(initalNumber).to.equal(0n);

    // Please only use prime number in this test
    const { transaction_hash: transferTxHash } = await account.execute([
      testDappContract.populateTransaction.set_number(1),
      testDappContract.populateTransaction.set_number_double(3),
      testDappContract.populateTransaction.set_number_times3(5),
      testDappContract.populateTransaction.set_number(7),
      testDappContract.populateTransaction.set_number_times3(11),
    ]);
    await account.waitForTransaction(transferTxHash);

    const finalNumber = await testDappContract.get_number(account.address);
    expect(finalNumber).to.equal(33n);
  });

  it("Expect an error when a multicall contains a Call referencing the account itself", async function () {
    const account = await deployAccount(argentAccountClassHash);
    const accountContract = await loadContract(account.address);

    await expectRevertWithErrorMessage("argent/no-multicall-to-self", async () => {
      const recipient = "0x42";
      const amount = uint256.bnToUint256(1000);
      const newOwner = "0x69";
      await account.execute([
        ethContract.populateTransaction.transfer(recipient, amount),
        accountContract.populateTransaction.trigger_escape_owner(newOwner),
      ]);
    });
  });
});
