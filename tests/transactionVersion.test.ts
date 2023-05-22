import { expect } from "chai";
import {Contract, InvocationsDetails, num, shortString} from "starknet";
import {
  ArgentSigner,
  OutsideExecution,
  declareContract,
  deployAccount,
  deployer,
  expectExecutionRevert,
  getOutsideCall,
  getOutsideExecutionCall,
  getTypedDataHash,
  loadContract,
  provider,
  randomPrivateKey,
  setTime,
  waitForTransaction,
} from "./lib";


describe.only("Transaction versions", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;
  let testDapp: Contract;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it("Fail with incorrect transaction version", async function () {
    const { account, accountContract } = await deployAccount(argentAccountClassHash);
    const call =testDapp.populateTransaction.set_number(42);

    await waitForTransaction( await account.execute(call, undefined, { maxFee: 0.01}))

  });
});
