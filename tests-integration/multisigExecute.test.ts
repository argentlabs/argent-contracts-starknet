import { expect } from "chai";
import { CallData, Contract } from "starknet";
import {
  MultisigSigner,
  declareContract,
  deployMultisig,
  deployer,
  expectEvent,
  expectRevertWithErrorMessage,
  loadContract,
  deployMultisig1_1,
} from "./lib";

describe("ArgentMultisig: Execute", function () {
  let testDappContract: Contract;

  before(async () => {
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDappContract = await loadContract(contract_address);
  });

  it("Should be able to execute a transaction using one owner when (signer_list = 1, threshold = 1)", async function () {
    const { account } = await deployMultisig1_1();

    await testDappContract.get_number(account.address).should.eventually.equal(0n);

    testDappContract.connect(account);
    const { transaction_hash } = await testDappContract.increase_number(42);

    const finalNumber = await testDappContract.get_number(account.address);
    expect(finalNumber).to.equal(42n);

    await expectEvent(transaction_hash, {
      from_address: account.address,
      eventName: "TransactionExecuted",
      additionalKeys: [transaction_hash],
      data: CallData.compile([[[finalNumber]]]),
    });
  });

  it("Should be able to execute a transaction using one owner when (signer_list > 1, threshold = 1) ", async function () {
    const { account, keys } = await deployMultisig({ threshold: 1, signersLength: 3 });

    account.signer = new MultisigSigner(keys.slice(0, 1));

    testDappContract.connect(account);
    await testDappContract.set_number(42);

    await testDappContract.get_number(account.address).should.eventually.equal(42n);
  });

  it("Should be able to execute a transaction using multiple owners when (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    account.signer = new MultisigSigner(keys.slice(0, 3));

    testDappContract.connect(account);
    await testDappContract.set_number(42);

    await testDappContract.get_number(account.address).should.eventually.equal(42n);
  });

  it("Should be able to execute multiple transactions using multiple owners when (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    account.signer = new MultisigSigner(keys.slice(0, 3));
    const calls = await account.execute([
      testDappContract.populateTransaction.increase_number(2),
      testDappContract.populateTransaction.increase_number(40),
    ]);

    await account.waitForTransaction(calls.transaction_hash);

    await testDappContract.get_number(account.address).should.eventually.equal(42n);
  });

  it("Expect 'argent/signatures-not-sorted' when signed tx is given in the wrong order (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    testDappContract.connect(account);

    // change order of signers
    const wrongSignerOrder = [keys[1], keys[3], keys[0]];
    account.signer = new MultisigSigner(wrongSignerOrder);

    await expectRevertWithErrorMessage(
      "argent/signatures-not-sorted",
      async () => await testDappContract.set_number(42),
    );
  });

  it("Expect 'argent/signatures-not-sorted' when tx is signed by one owner twice (signer_list > 1, threshold > 1)", async function () {
    const { account, keys } = await deployMultisig({ threshold: 3, signersLength: 5 });

    testDappContract.connect(account);

    // repeated signers
    const repeatedSigners = [keys[0], keys[0], keys[1]];
    account.signer = new MultisigSigner(repeatedSigners);

    await expectRevertWithErrorMessage(
      "argent/signatures-not-sorted",
      async () => await testDappContract.set_number(42),
    );
  });
});
