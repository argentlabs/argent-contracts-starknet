import { expect } from "chai";
import { Contract, num } from "starknet";
import {
  ArgentSigner,
  ExternalExecution,
  declareContract,
  deployAccount,
  deployerAccount,
  expectExecutionRevert,
  getExternalCall,
  getExternalExecutionCall,
  getTypedDataHash,
  loadContract,
  provider,
  randomPrivateKey,
  setTime,
  waitForExecution,
} from "./shared";

const initialTime = 1713139200;
describe("Test external execution", function () {
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

    const externalExecution: ExternalExecution = {
      sender: deployerAccount.address,
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
      await accountContract.get_message_hash_external_execution(externalExecution, { nonce: undefined }),
    );
    const expectedMessageHash = getTypedDataHash(externalExecution, account.address, chainId);
    expect(foundHash).to.equal(expectedMessageHash);
  });

  it("Basics", async function () {
    const accountSigner = new ArgentSigner(randomPrivateKey(), randomPrivateKey());
    const account = await deployAccount(
      argentAccountClassHash,
      accountSigner.ownerPrivateKey,
      accountSigner.guardianPrivateKey,
    );

    expect(await testDapp.get_number(account.address)).eql(0n, "invalid initial value");

    const externalExecution: ExternalExecution = {
      sender: deployerAccount.address,
      nonce: randomPrivateKey(),
      min_timestamp: initialTime - 100,
      max_timestamp: initialTime + 100,
      calls: [getExternalCall(testDapp.populateTransaction.set_number(42))],
    };
    const externalExecutionCall = await getExternalExecutionCall(externalExecution, account.address, accountSigner);

    // ensure can't be run too early
    await setTime(initialTime - 200);
    await expectExecutionRevert("argent/invalid-timestamp", deployerAccount.execute(externalExecutionCall));

    // ensure can't be run too late
    await setTime(initialTime + 200);
    await expectExecutionRevert("argent/invalid-timestamp", deployerAccount.execute(externalExecutionCall));

    // ensure the sender is as expected
    await expectExecutionRevert(
      "argent/invalid-caller",
      deployerAccount.execute(
        await getExternalExecutionCall({ ...externalExecution, sender: "0x123" }, account.address, accountSigner),
      ),
    );

    await setTime(initialTime);

    // ensure the account address is checked
    const wrongAccountCall = await getExternalExecutionCall(externalExecution, "0x123", accountSigner);
    await expectExecutionRevert(
      "argent/invalid-owner-sig",
      deployerAccount.execute({ ...wrongAccountCall, contractAddress: account.address }),
    );

    // ensure the chain id is checked
    await expectExecutionRevert(
      "argent/invalid-owner-sig",
      deployerAccount.execute(
        await getExternalExecutionCall(externalExecution, account.address, accountSigner, "ANOTHER_CHAIN"),
      ),
    );

    // normal scenario
    await waitForExecution(deployerAccount.execute(externalExecutionCall));
    expect(await testDapp.get_number(account.address)).eql(42n, "invalid new value");

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/repeated-external-nonce", deployerAccount.execute(externalExecutionCall));
  });

  it("Owner only account", async function () {
    const accountSigner = new ArgentSigner();
    const account = await deployAccount(argentAccountClassHash, accountSigner.ownerPrivateKey);

    const externalExecution: ExternalExecution = {
      sender: deployerAccount.address,
      nonce: randomPrivateKey(),
      min_timestamp: 0,
      max_timestamp: initialTime + 100,
      calls: [getExternalCall(testDapp.populateTransaction.set_number(42))],
    };
    const externalExecutionCall = await getExternalExecutionCall(externalExecution, account.address, accountSigner);

    await setTime(initialTime);

    await waitForExecution(deployerAccount.execute(externalExecutionCall));
    expect(await testDapp.get_number(account.address)).eql(42n, "invalid new value");
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

    const externalExecution: ExternalExecution = {
      sender: deployerAccount.address,
      nonce: randomPrivateKey(),
      min_timestamp: 0,
      max_timestamp: initialTime + 100,
      calls: [getExternalCall(accountContract.populateTransaction.trigger_escape_owner(42))],
    };
    const externalExecutionCall = await getExternalExecutionCall(
      externalExecution,
      account.address,
      guardianOnlySigner,
    );

    await waitForExecution(deployerAccount.execute(externalExecutionCall));
    const current_escape = await accountContract.get_escape();
    expect(current_escape.new_signer).eql(42n, "invalid new value");
  });
});
