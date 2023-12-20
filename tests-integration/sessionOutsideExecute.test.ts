import { expect } from "chai";
import { Contract, uint256, selector } from "starknet";
import {
  ArgentSigner,
  OutsideExecution,
  declareContract,
  deployAccount,
  deployer,
  expectExecutionRevert,
  getOutsideCall,
  getOutsideExecutionCallWithSession,
  getTypedDataHash,
  loadContract,
  provider,
  randomKeyPair,
  setTime,
  waitForTransaction,
  BackendService,
  DappService,
  ArgentX,
  AllowedMethod,
  TokenAmount,
  DappSigner,
} from "./lib";

const tokenAmounts: TokenAmount[] = [{ token_address: "0x100", amount: uint256.bnToUint256(10) }];

const initialTime = 1713139200;
describe("ArgentAccount: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;
  let testDapp: Contract;

  before(async () => {
    argentAccountClassHash = await declareContract("HybridSessionAccount");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it.only("Basics", async function () {
    const { account, accountContract, guardian } = await deployAccount(argentAccountClassHash);

    await testDapp.get_number(account.address).should.eventually.equal(0n, "invalid initial value");

    const outsideExecution: OutsideExecution = {
      caller: deployer.address,
      nonce: randomKeyPair().publicKey,
      execute_after: initialTime - 100,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCallWithSession(
      outsideExecution,
      account.address,
      account.signer,
    );

    // ensure can't be run too early
    await setTime(initialTime - 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure can't be run too late
    await setTime(initialTime + 200);
    await expectExecutionRevert("argent/invalid-timestamp", () => deployer.execute(outsideExecutionCall));

    // ensure the caller is as expected
    await expectExecutionRevert("argent/invalid-caller", async () =>
      deployer.execute(
        await getOutsideExecutionCallWithSession(
          { ...outsideExecution, caller: "0x123" },
          account.address,
          account.signer,
        ),
      ),
    );

    await setTime(initialTime);

    // normal scenario
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(true);

    const backendService = new BackendService(guardian);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": testDapp.address,
        selector: selector.getSelectorFromName("set_number"),
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, tokenAmounts);

    // 2. Owner and Guardian signs session
    const accountSessionSignature = await argentX.getAccountSessionSignature(sessionRequest);

    //  Every request:
    const calls = [testDapp.populateTransaction.set_number(2)];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const sessionSigner = new DappSigner(
      argentX,
      backendService,
      dappService.keypair,
      accountSessionSignature,
      sessionRequest,
    );

    account.signer = sessionSigner;

    await account.execute(outsideExecutionCall);

    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => deployer.execute(outsideExecutionCall));
  });
});
