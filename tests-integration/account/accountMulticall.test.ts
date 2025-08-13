import { expect } from "chai";
import { Contract, uint256 } from "starknet";
import { deployAccount, expectEvent, expectRevertWithErrorMessage, manager, randomStarknetKeyPair } from "../../lib";

describe("ArgentAccount: multicall", function () {
  let mockDappContract: Contract;
  let strkContract: Contract;

  before(async () => {
    mockDappContract = await manager.declareAndDeployContract("MockDapp");
    strkContract = await manager.tokens.strkContract();
  });

  it("Should be possible to send strk", async function () {
    const { account } = await deployAccount();
    const recipient = "0x42";
    const amount = uint256.bnToUint256(1000);
    const senderInitialBalance = await manager.tokens.strkBalance(account.address);
    const recipientInitialBalance = await manager.tokens.strkBalance(recipient);
    strkContract.connect(account);
    const { transaction_hash } = await strkContract.transfer(recipient, amount);
    await account.waitForTransaction(transaction_hash);

    const senderFinalBalance = await manager.tokens.strkBalance(account.address);
    const recipientFinalBalance = await manager.tokens.strkBalance(recipient);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(senderInitialBalance + 1000n > senderFinalBalance).to.be.true;
    expect(recipientInitialBalance + 1000n).to.equal(recipientFinalBalance);

    await expectEvent(transaction_hash, {
      from_address: account.address,
      eventName: "TransactionExecuted",
      keys: [transaction_hash],
      data: [],
    });
  });

  it("Should be possible to send strk with a Cairo1 account using a multicall", async function () {
    const { account } = await deployAccount();
    const recipient1 = "42";
    const amount1 = uint256.bnToUint256(1000);
    const recipient2 = "43";
    const amount2 = uint256.bnToUint256(42000);

    const senderInitialBalance = await manager.tokens.strkBalance(account.address);
    const recipient1InitialBalance = await manager.tokens.strkBalance(recipient1);
    const recipient2InitialBalance = await manager.tokens.strkBalance(recipient2);

    const { transaction_hash: transferTxHash } = await account.execute([
      strkContract.populateTransaction.transfer(recipient1, amount1),
      strkContract.populateTransaction.transfer(recipient2, amount2),
    ]);
    await account.waitForTransaction(transferTxHash);

    const senderFinalBalance = await manager.tokens.strkBalance(account.address);
    const recipient1FinalBalance = await manager.tokens.strkBalance(recipient1);
    const recipient2FinalBalance = await manager.tokens.strkBalance(recipient2);
    expect(senderInitialBalance > senderFinalBalance + 1000n + 4200n).to.be.true;
    expect(recipient1InitialBalance + 1000n).to.equal(recipient1FinalBalance);
    expect(recipient2InitialBalance + 42000n).to.equal(recipient2FinalBalance);
  });

  it("Should be possible to invoke different contracts in a multicall", async function () {
    const { account } = await deployAccount();
    const recipient1 = "42";
    const amount1 = uint256.bnToUint256(1000);

    const senderInitialBalance = await manager.tokens.strkBalance(account.address);
    const recipient1InitialBalance = await manager.tokens.strkBalance(recipient1);
    const initialNumber = await mockDappContract.get_number(account.address);
    expect(initialNumber).to.equal(0n);

    const { transaction_hash: transferTxHash } = await account.execute([
      strkContract.populateTransaction.transfer(recipient1, amount1),
      mockDappContract.populateTransaction.set_number(42),
    ]);
    await account.waitForTransaction(transferTxHash);

    const senderFinalBalance = await manager.tokens.strkBalance(account.address);
    const recipient1FinalBalance = await manager.tokens.strkBalance(recipient1);
    const finalNumber = await mockDappContract.get_number(account.address);
    // Before amount should be higher than (after + transfer) amount due to fee
    expect(Number(senderInitialBalance)).to.be.greaterThan(Number(senderFinalBalance) + 1000 + 42000);
    expect(recipient1InitialBalance + 1000n).to.equal(recipient1FinalBalance);
    expect(finalNumber).to.equal(42n);
  });

  it("Should keep the tx in correct order", async function () {
    const { account } = await deployAccount();

    const initialNumber = await mockDappContract.get_number(account.address);
    expect(initialNumber).to.equal(0n);

    // Please only use prime number in this test
    const { transaction_hash: transferTxHash } = await account.execute([
      mockDappContract.populateTransaction.set_number(1),
      mockDappContract.populateTransaction.set_number_double(3),
      mockDappContract.populateTransaction.set_number_times3(5),
      mockDappContract.populateTransaction.set_number(7),
      mockDappContract.populateTransaction.set_number_times3(11),
    ]);
    await account.waitForTransaction(transferTxHash);

    const finalNumber = await mockDappContract.get_number(account.address);
    expect(finalNumber).to.equal(33n);
  });

  it("Expect an error when a multicall contains a Call referencing the account itself", async function () {
    const { account, accountContract } = await deployAccount();
    const recipient = "42";
    const amount = uint256.bnToUint256(1000);
    const newOwner = randomStarknetKeyPair();

    await expectRevertWithErrorMessage(
      "argent/no-multicall-to-self",
      account.execute([
        strkContract.populateTransaction.transfer(recipient, amount),
        accountContract.populateTransaction.trigger_escape_owner(newOwner.compiledSigner),
      ]),
    );
  });
});
