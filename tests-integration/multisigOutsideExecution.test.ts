import { expect } from "chai";
import { Contract, num, shortString } from "starknet";
import {
  OutsideExecution,
  deployer,
  expectExecutionRevert,
  getOutsideCall,
  getOutsideExecutionCall,
  getTypedDataHash,
  deployContract,
  provider,
  randomKeyPair,
  setTime,
  waitForTransaction,
} from "./lib";
import { deployMultisig } from "./lib/multisig";

const initialTime = 1713139200;
describe("ArgentMultisig: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let testDapp: Contract;

  before(async () => {
    testDapp = await deployContract("TestDapp");
  });

  it("Correct message hash", async function () {
    const { accountContract } = await deployMultisig({ threshold: 1, signersLength: 2 });

    const chainId = await provider.getChainId();

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      execute_after: 0,
      execute_before: 1713139200,
      nonce: randomKeyPair().privateKey,
      calls: [
        {
          to: "0x0424242",
          selector: "0x42",
          calldata: ["0x0", "0x1"],
        },
      ],
    };

    const foundHash = num.toHex(
      await accountContract.get_outside_execution_message_hash(outsideExecution, { nonce: undefined }),
    );
    const expectedMessageHash = getTypedDataHash(outsideExecution, accountContract.address, chainId);
    expect(foundHash).to.equal(expectedMessageHash);
  });

  it("Basics", async function () {
    const { account, accountContract } = await deployMultisig({ threshold: 1, signersLength: 2 });
    await testDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      nonce: randomKeyPair().privateKey,
      execute_after: initialTime - 100,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, account.signer);

    // ensure can't be run too early
    await setTime(initialTime - 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure can't be run too late
    await setTime(initialTime + 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure the caller is as expected
    await expectExecutionRevert("argent/invalid-caller", async () =>
      deployer.execute(
        await getOutsideExecutionCall({ ...outsideExecution, caller: "0x123" }, account.address, account.signer),
      ),
    );

    await setTime(initialTime);

    // ensure the account address is checked
    const wrongAccountCall = await getOutsideExecutionCall(outsideExecution, "0x123", account.signer);
    await expectExecutionRevert("argent/invalid-signature", () =>
      deployer.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert("argent/invalid-signature", async () =>
      deployer.execute(
        await getOutsideExecutionCall(outsideExecution, account.address, account.signer, "ANOTHER_CHAIN"),
      ),
    );

    // normal scenario
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(true);
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });

  it("Avoid caller check if it caller is ANY_CALLER", async function () {
    const { account } = await deployMultisig({ threshold: 1, signersLength: 2 });

    await testDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: shortString.encodeShortString("ANY_CALLER"),
      nonce: randomKeyPair().privateKey,
      execute_after: 0,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, account.signer);

    await setTime(initialTime);

    // ensure the caller is not used
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });
});
