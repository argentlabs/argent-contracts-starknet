import { expect } from "chai";
import { Contract, num, shortString } from "starknet";
import {
  ArgentSigner,
  OutsideExecution,
  declareContract,
  deployAccount,
  deployerAccount,
  expectExecutionRevert,
  getOutsideCall,
  getOutsideExecutionCall,
  getTypedDataHash,
  loadContract,
  provider,
  randomPrivateKey,
  setTime,
  waitForExecution,
} from "./shared";

const initialTime = 1713139200;
describe("Test outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;
  let testDapp: Contract;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    const testDappClassHash = await declareContract("TestDapp");
    const { transaction_hash, contract_address } = await deployerAccount.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it("Correct message hash", async function () {
    const account = await deployAccount(argentAccountClassHash);
    const accountContract = await loadContract(account.address);

    const chainId = await provider.getChainId();

    const outsideExecution: OutsideExecution = {
      caller: deployerAccount.address,
      min_timestamp: 0,
      max_timestamp: 1713139200,
      nonce: randomPrivateKey(),
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
    const expectedMessageHash = getTypedDataHash(outsideExecution, account.address, chainId);
    expect(foundHash).to.equal(expectedMessageHash);
  });

  it("Basics", async function () {
    const accountSigner = new ArgentSigner(randomPrivateKey(), randomPrivateKey());
    const account = await deployAccount(
      argentAccountClassHash,
      accountSigner.ownerPrivateKey,
      accountSigner.guardianPrivateKey,
    );

    await testDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: deployerAccount.address,
      nonce: randomPrivateKey(),
      min_timestamp: initialTime - 100,
      max_timestamp: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, accountSigner);

    // ensure can't be run too early
    await setTime(initialTime - 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployerAccount.execute(outsideExecutionCall));

    // ensure can't be run too late
    await setTime(initialTime + 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployerAccount.execute(outsideExecutionCall));

    // ensure the caller is as expected
    await expectExecutionRevert("argent/invalid-caller", async () =>
      deployerAccount.execute(
        await getOutsideExecutionCall({ ...outsideExecution, caller: "0x123" }, account.address, accountSigner),
      ),
    );

    await setTime(initialTime);

    // ensure the account address is checked
    const wrongAccountCall = await getOutsideExecutionCall(outsideExecution, "0x123", accountSigner);
    await expectExecutionRevert("argent/invalid-owner-sig", () =>
      deployerAccount.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert("argent/invalid-owner-sig", async () =>
      deployerAccount.execute(
        await getOutsideExecutionCall(outsideExecution, account.address, accountSigner, "ANOTHER_CHAIN"),
      ),
    );

    // normal scenario
    await waitForExecution(deployerAccount.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployerAccount.execute(outsideExecutionCall));
  });

  it("Avoid caller check if it caller is ANY_CALLER", async function () {
    const accountSigner = new ArgentSigner(randomPrivateKey(), randomPrivateKey());
    const account = await deployAccount(
      argentAccountClassHash,
      accountSigner.ownerPrivateKey,
      accountSigner.guardianPrivateKey,
    );

    await testDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: shortString.encodeShortString("ANY_CALLER"),
      nonce: randomPrivateKey(),
      min_timestamp: 0,
      max_timestamp: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, accountSigner);

    // ensure the caller is no
    await waitForExecution(deployerAccount.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });

  it("Owner only account", async function () {
    const accountSigner = new ArgentSigner();
    const account = await deployAccount(argentAccountClassHash, accountSigner.ownerPrivateKey);

    const outsideExecution: OutsideExecution = {
      caller: deployerAccount.address,
      nonce: randomPrivateKey(),
      min_timestamp: 0,
      max_timestamp: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, accountSigner);

    await setTime(initialTime);

    await waitForExecution(deployerAccount.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });

  it("Escape method", async function () {
    const accountSigner = new ArgentSigner(randomPrivateKey(), randomPrivateKey());
    const guardianOnlySigner = new ArgentSigner(accountSigner.guardianPrivateKey);

    const account = await deployAccount(
      argentAccountClassHash,
      accountSigner.ownerPrivateKey,
      accountSigner.guardianPrivateKey,
    );

    const accountContract = await loadContract(account.address);

    const outsideExecution: OutsideExecution = {
      caller: deployerAccount.address,
      nonce: randomPrivateKey(),
      min_timestamp: 0,
      max_timestamp: initialTime + 100,
      calls: [getOutsideCall(accountContract.populateTransaction.trigger_escape_owner(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, guardianOnlySigner);

    await waitForExecution(deployerAccount.execute(outsideExecutionCall));
    const current_escape = await accountContract.get_escape();
    expect(current_escape.new_signer).eql(42n, "invalid new value");
  });
});
