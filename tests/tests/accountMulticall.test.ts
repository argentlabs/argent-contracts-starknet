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

  it("Should be possible to send eth", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    const recipient = "0x42";
    const amount = uint256.bnToUint256(1000);
    const senderInitialBalance = await getEthBalance(ethContract, account.address);
    const recipientInitialBalance = await getEthBalance(ethContract, recipient);
    ethContract.connect(account);
    // TODO it should be possible to do this at some point
    // await ethContract.transfer(recipient, amount);
    const { transaction_hash: transferTxHash } = await account.execute(
      ethContract.populateTransaction.transfer(recipient, amount),
    );

    await account.waitForTransaction(transferTxHash);
    const senderFinalBalance = await getEthBalance(ethContract, account.address);
    const recipientFinalBalance = await getEthBalance(ethContract, recipient);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(senderInitialBalance + 1000n > senderFinalBalance).to.be.true;
    expect(recipientInitialBalance + 1000n).to.equal(recipientFinalBalance);
  });

  it("Should be possible to send eth with a Cairo1 account using a multicall", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    const recipient1 = "42";
    const amount1 = uint256.bnToUint256(1000);
    const recipient2 = "43";
    const amount2 = uint256.bnToUint256(42000);

    const senderInitialBalance = await getEthBalance(ethContract, account.address);
    const recipient1InitialBalance = await getEthBalance(ethContract, recipient1);
    const recipient2InitialBalance = await getEthBalance(ethContract, recipient2);

    const { transaction_hash: transferTxHash } = await account.execute([
      ethContract.populateTransaction.transfer(recipient1, amount1),
      ethContract.populateTransaction.transfer(recipient2, amount2),
    ]);
    await account.waitForTransaction(transferTxHash);

    const senderFinalBalance = await getEthBalance(ethContract, account.address);
    const recipient1FinalBalance = await getEthBalance(ethContract, recipient1);
    const recipient2FinalBalance = await getEthBalance(ethContract, recipient2);
    expect(senderInitialBalance > senderFinalBalance + 1000n + 4200n).to.be.true;
    expect(recipient1InitialBalance + 1000n).to.equal(recipient1FinalBalance);
    expect(recipient2InitialBalance + 42000n).to.equal(recipient2FinalBalance);
  });

  it("Should be possible to invoke different contracts in a multicall", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    const recipient1 = "42";
    const amount1 = uint256.bnToUint256(1000);

    const senderInitialBalance = await getEthBalance(ethContract, account.address);
    const recipient1InitialBalance = await getEthBalance(ethContract, recipient1);
    const initalNumber = await testDappContract.get_number(account.address);
    expect(initalNumber).to.equal(0n);

    const { transaction_hash: transferTxHash } = await account.execute([
      ethContract.populateTransaction.transfer(recipient1, amount1),
      testDappContract.populateTransaction.set_number(42),
    ]);
    await account.waitForTransaction(transferTxHash);

    const senderFinalBalance = await getEthBalance(ethContract, account.address);
    const recipient1FinalBalance = await getEthBalance(ethContract, recipient1);
    const finalNumber = await testDappContract.get_number(account.address);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(Number(senderInitialBalance)).to.be.greaterThan(Number(senderFinalBalance) + 1000 + 42000);
    expect(recipient1InitialBalance + 1000n).to.equal(recipient1FinalBalance);
    expect(finalNumber).to.equal(42n);
  });

  it("Should keep the tx in correct order", async function () {
    const { account } = await deployAccount(argentAccountClassHash);

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
    const { account, accountContract } = await deployAccount(argentAccountClassHash);
    const recipient = "42";
    const amount = uint256.bnToUint256(1000);
    const newOwner = "69";

    await expectRevertWithErrorMessage("argent/no-multicall-to-self", () =>
      account.execute([
        ethContract.populateTransaction.transfer(recipient, amount),
        accountContract.populateTransaction.trigger_escape_owner(newOwner),
      ]),
    );
  });
});

async function getEthBalance(ethContract: Contract, accountAddress: string): Promise<bigint> {
  return uint256.uint256ToBN((await ethContract.balanceOf(accountAddress)).balance);
}