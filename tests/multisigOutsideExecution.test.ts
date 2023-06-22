import { expect } from "chai";
import { Contract, num, shortString } from "starknet";
import {
  OutsideExecution,
  declareContract,
  deployer,
  expectExecutionRevert,
  getOutsideCall,
  getOutsideExecutionCall,
  getTypedDataHash,
  loadContract,
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

  let multisigClassHash: string;
  let testDapp: Contract;

  before(async () => {
    multisigClassHash = await declareContract("ArgentMultisig");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it("Correct message hash", async function () {
    const { IAccount } = await deployMultisig(multisigClassHash, 1 /* threshold */, 2 /* signers count */);

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
      await IAccount.get_outside_execution_message_hash(outsideExecution, { nonce: undefined }),
    );
    const expectedMessageHash = getTypedDataHash(outsideExecution, IAccount.address, chainId);
    expect(foundHash).to.equal(expectedMessageHash);
  });

  it("Basics", async function () {
    const { account } = await deployMultisig(multisigClassHash, 1 /* threshold */, 2 /* signers count */);
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
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });

  it("Avoid caller check if it caller is ANY_CALLER", async function () {
    const { account } = await deployMultisig(multisigClassHash, 1 /* threshold */, 2 /* signers count */);

    await testDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: shortString.encodeShortString("ANY_CALLER"),
      nonce: randomKeyPair().privateKey,
      execute_after: 0,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCall(outsideExecution, account.address, account.signer);

    // ensure the caller is not used
    await waitForTransaction(await deployer.execute(outsideExecutionCall));
    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });
});
