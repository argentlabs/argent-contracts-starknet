import { expect } from "chai";
import { Contract } from "starknet";
import {
  MultisigSigner,
  deployMultisig,
  deployMultisig1_1,
  expectEvent,
  expectRevertWithErrorMessage,
  generateRandomNumber,
  manager,
  sortByGuid,
} from "../../lib";

describe("ArgentMultisig: Execute", function () {
  let mockDappContract: Contract;
  let randomNumber: bigint;

  before(async () => {
    mockDappContract = await manager.declareAndDeployContract("MockDapp");
  });

  beforeEach(async () => {
    randomNumber = generateRandomNumber();
  });

  for (const useTxV3 of [false, true]) {
    it(`Should be able to execute a transaction using one owner when (signer_list = 1, threshold = 1) (TxV3:${useTxV3})`, async function () {
      const { account } = await deployMultisig1_1({ useTxV3 });

      await mockDappContract.get_number(account.address).should.eventually.equal(0n);

      mockDappContract.connect(account);
      const { transaction_hash } = await mockDappContract.increase_number(randomNumber);

      const finalNumber = await mockDappContract.get_number(account.address);
      expect(finalNumber).to.equal(randomNumber);

      await expectEvent(transaction_hash, {
        from_address: account.address,
        eventName: "TransactionExecuted",
        keys: [transaction_hash],
        data: [],
      });
    });
  }

  it("Should be able to execute a transaction using one owner when (signer_list > 1, threshold = 1) ", async function () {
    const { account, keys } = await deployMultisig({ threshold: 1, signersLength: 3 });

    account.signer = new MultisigSigner(sortByGuid(keys).slice(0, 1));

    mockDappContract.connect(account);
    await mockDappContract.set_number(randomNumber);

    await mockDappContract.get_number(account.address).should.eventually.equal(randomNumber);
  });

  it("Should be able to execute a transaction using multiple owners when (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    account.signer = new MultisigSigner(sortByGuid(keys).slice(0, 3));

    mockDappContract.connect(account);
    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];
    await account.execute(calls);

    await mockDappContract.get_number(account.address).should.eventually.equal(randomNumber);
  });

  it("Should be able to execute multiple transactions using multiple owners when (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    account.signer = new MultisigSigner(sortByGuid(keys).slice(0, 3));
    const calls = await account.execute([
      mockDappContract.populateTransaction.increase_number(2),
      mockDappContract.populateTransaction.increase_number(40),
    ]);

    await account.waitForTransaction(calls.transaction_hash);

    await mockDappContract.get_number(account.address).should.eventually.equal(42n);
  });

  it("Expect 'argent/signatures-not-sorted' when signed tx is given in the wrong order (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    mockDappContract.connect(account);

    // change order of signers
    const wrongSignerOrder = [keys[1], keys[3], keys[0]];
    account.signer = new MultisigSigner(wrongSignerOrder);

    await expectRevertWithErrorMessage("argent/signatures-not-sorted", mockDappContract.set_number(randomNumber));
  });

  it("Expect 'argent/signatures-not-sorted' when tx is signed by one owner twice (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    mockDappContract.connect(account);

    // repeated signers
    const repeatedSigners = [keys[0], keys[0], keys[1]];
    account.signer = new MultisigSigner(repeatedSigners);

    await expectRevertWithErrorMessage("argent/signatures-not-sorted", mockDappContract.set_number(randomNumber));
  });
});
