import { expect } from "chai";
import { Contract, TypedDataRevision, num, shortString } from "starknet";
import {
  OutsideExecution,
  deployer,
  expectExecutionRevert,
  expectRevertWithErrorMessage,
  getOutsideCall,
  getOutsideExecutionCall,
  getTypedDataHash,
  manager,
  randomStarknetKeyPair,
  waitForTransaction,
} from "../lib";
import { deployMultisig } from "../lib/multisig";

const legacyRevision = TypedDataRevision.LEGACY;
const activeRevision = TypedDataRevision.ACTIVE;

const initialTime = 1713139200;
describe("ArgentMultisig: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let mockDapp: Contract;

  before(async () => {
    mockDapp = await manager.deployContract("MockDapp");
  });

  it("Correct message hash", async function () {
    const { accountContract } = await deployMultisig({ threshold: 1, signersLength: 2 });

    const chainId = await manager.getChainId();

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      execute_after: 0,
      execute_before: 1713139200,
      nonce: randomStarknetKeyPair().privateKey,
      calls: [
        {
          to: "0x0424242",
          selector: "0x42",
          calldata: ["0x0", "0x1"],
        },
      ],
    };

    const foundHash = num.toHex(
      await accountContract.get_outside_execution_message_hash_rev_0(outsideExecution, { nonce: undefined }),
    );
    const expectedMessageHash = getTypedDataHash(outsideExecution, accountContract.address, chainId, legacyRevision);
    expect(foundHash).to.equal(expectedMessageHash);
  });

  it("Basics: Rev 0", async function () {
    const { account, accountContract } = await deployMultisig({ threshold: 1, signersLength: 2 });
    await mockDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      nonce: randomStarknetKeyPair().privateKey,
      execute_after: initialTime - 100,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(mockDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(
      outsideExecution,
      account.address,
      account.signer,
      legacyRevision,
    );

    // ensure can't be run too early
    await manager.setTime(initialTime - 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure can't be run too late
    await manager.setTime(initialTime + 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure the caller is as expected
    await expectExecutionRevert("argent/invalid-caller", async () =>
      deployer.execute(
        await getOutsideExecutionCall(
          { ...outsideExecution, caller: "0x123" },
          account.address,
          account.signer,
          legacyRevision,
        ),
      ),
    );

    await manager.setTime(initialTime);

    // ensure the account address is checked
    const wrongAccountCall = await getOutsideExecutionCall(outsideExecution, "0x123", account.signer, legacyRevision);
    await expectExecutionRevert("argent/invalid-signature", () =>
      deployer.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert("argent/invalid-signature", async () =>
      deployer.execute(
        await getOutsideExecutionCall(
          outsideExecution,
          account.address,
          account.signer,
          legacyRevision,
          "ANOTHER_CHAIN",
        ),
      ),
    );

    // normal scenario
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(true);
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });

  it("Avoid caller check if it caller is ANY_CALLER", async function () {
    const { account } = await deployMultisig({ threshold: 1, signersLength: 2 });

    await mockDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: shortString.encodeShortString("ANY_CALLER"),
      nonce: randomStarknetKeyPair().privateKey,
      execute_after: 0,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(mockDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(
      outsideExecution,
      account.address,
      account.signer,
      legacyRevision,
    );

    await manager.setTime(initialTime);

    // ensure the caller is not used
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });

  it("Basics: Rev 1", async function () {
    const { account, accountContract } = await deployMultisig({ threshold: 1, signersLength: 2 });
    await mockDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      nonce: randomStarknetKeyPair().publicKey,
      execute_after: initialTime - 100,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(mockDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(
      outsideExecution,
      account.address,
      account.signer,
      legacyRevision,
    );

    // ensure can't be run too early
    await manager.setTime(initialTime - 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure can't be run too late
    await manager.setTime(initialTime + 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure the caller is as expected
    await expectExecutionRevert("argent/invalid-caller", async () =>
      deployer.execute(
        await getOutsideExecutionCall(
          { ...outsideExecution, caller: "0x123" },
          account.address,
          account.signer,
          legacyRevision,
        ),
      ),
    );

    await manager.setTime(initialTime);

    // ensure the account address is checked
    const wrongAccountCall = await getOutsideExecutionCall(outsideExecution, "0x123", account.signer, legacyRevision);
    await expectExecutionRevert("argent/invalid-signature", () =>
      deployer.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert("argent/invalid-signature", async () =>
      deployer.execute(
        await getOutsideExecutionCall(
          outsideExecution,
          account.address,
          account.signer,
          legacyRevision,
          "ANOTHER_CHAIN",
        ),
      ),
    );

    // normal scenario
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(true);
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });

  it("Avoid caller check if it caller is ANY_CALLER", async function () {
    const { account } = await deployMultisig({ threshold: 1, signersLength: 2 });

    await mockDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: shortString.encodeShortString("ANY_CALLER"),
      nonce: randomStarknetKeyPair().publicKey,
      execute_after: 0,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(mockDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(
      outsideExecution,
      account.address,
      account.signer,
      legacyRevision,
    );

    await manager.setTime(initialTime);

    // ensure the caller is not used
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });

  it("No reentrancy", async function () {
    const { account, accountContract } = await deployMultisig({ threshold: 1, signersLength: 2 });

    const outsideExecutionCall = await getOutsideExecutionCall(
      {
        caller: shortString.encodeShortString("ANY_CALLER"),
        nonce: randomStarknetKeyPair().publicKey,
        execute_after: 0,
        execute_before: initialTime + 100,
        calls: [getOutsideCall(accountContract.populateTransaction.change_threshold(2))],
      },
      account.address,
      account.signer,
      activeRevision,
    );

    await manager.setTime(initialTime);

    await expectRevertWithErrorMessage("ReentrancyGuard: reentrant call", () => account.execute(outsideExecutionCall));
  });
});
