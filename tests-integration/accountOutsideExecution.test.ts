import { expect } from "chai";
import { Contract, TypedDataRevision, num, shortString } from "starknet";
import {
  ArgentSigner,
  OutsideExecution,
  deployAccount,
  deployer,
  expectExecutionRevert,
  expectRevertWithErrorMessage,
  getOutsideCall,
  getOutsideExecutionCall,
  getTypedDataHash,
  manager,
  randomStarknetKeyPair,
} from "../lib";

const activeRevision = TypedDataRevision.ACTIVE;
const legacyRevision = TypedDataRevision.LEGACY;

const initialTime = 1713139200;
describe("ArgentAccount: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let mockDapp: Contract;

  before(async () => {
    mockDapp = await manager.deployContract("MockDapp");
  });

  it("Correct message hash", async function () {
    const { account, accountContract } = await deployAccount();

    const chainId = await manager.getChainId();

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      execute_after: 0,
      execute_before: 1713139200,
      nonce: randomStarknetKeyPair().publicKey,
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
    const expectedMessageHash = getTypedDataHash(outsideExecution, account.address, chainId, legacyRevision);
    expect(foundHash).to.equal(expectedMessageHash);
  });

  it("Basics: Rev 0", async function () {
    const { account, accountContract } = await deployAccount();

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
    await expectExecutionRevert("argent/invalid-owner-sig", () =>
      deployer.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert("argent/invalid-owner-sig", async () =>
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
    await manager.waitForTx(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });

  it("Basics: Revision 1", async function () {
    const { account, accountContract } = await deployAccount();

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
      activeRevision,
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
          activeRevision,
        ),
      ),
    );

    await manager.setTime(initialTime);

    // ensure the account address is checked
    const wrongAccountCall = await getOutsideExecutionCall(outsideExecution, "0x123", account.signer, activeRevision);
    await expectExecutionRevert("argent/invalid-owner-sig", () =>
      deployer.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert("argent/invalid-owner-sig", async () =>
      deployer.execute(
        await getOutsideExecutionCall(
          outsideExecution,
          account.address,
          account.signer,
          activeRevision,
          "ANOTHER_CHAIN",
        ),
      ),
    );

    // normal scenario
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(true);
    await manager.waitForTx(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });

  it("Avoid caller check if it caller is ANY_CALLER", async function () {
    const { account } = await deployAccount();

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

    // ensure the caller is no
    await manager.waitForTx(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });

  it("Owner only account", async function () {
    const { account } = await deployAccount();

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
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

    await manager.waitForTx(await deployer.execute(outsideExecutionCall));
    await mockDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });

  it("Escape method", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    const keyPair = randomStarknetKeyPair();

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      nonce: randomStarknetKeyPair().publicKey,
      execute_after: 0,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(accountContract.populateTransaction.trigger_escape_owner(keyPair.compiledSigner))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(
      outsideExecution,
      account.address,
      new ArgentSigner(guardian),
      legacyRevision,
    );

    await manager.setTime(initialTime);

    await manager.waitForTx(await deployer.execute(outsideExecutionCall));
    const current_escape = await accountContract.get_escape();
    expect(current_escape.new_signer.unwrap().stored_value).to.equal(keyPair.storedValue);
  });

  it("No reentrancy", async function () {
    const { account, accountContract, guardian } = await deployAccount();

    const outsideExecutionCall = await getOutsideExecutionCall(
      {
        caller: shortString.encodeShortString("ANY_CALLER"),
        nonce: randomStarknetKeyPair().publicKey,
        execute_after: 0,
        execute_before: initialTime + 100,
        calls: [
          getOutsideCall(
            accountContract.populateTransaction.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
          ),
        ],
      },
      account.address,
      new ArgentSigner(guardian),
      activeRevision,
    );

    await manager.setTime(initialTime);

    await expectRevertWithErrorMessage("ReentrancyGuard: reentrant call", account.execute(outsideExecutionCall));
  });
});
