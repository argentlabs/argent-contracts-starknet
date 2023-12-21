import { expect } from "chai";
import { Contract, uint256, selector, Account } from "starknet";
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

const tokenAmounts: TokenAmount[] = [];

const initialTime = 1713139200;
describe("ArgentAccount: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentSessionAccountClassHash: string;
  let testDapp: Contract;

  before(async () => {
    argentSessionAccountClassHash = await declareContract("HybridSessionAccount");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it.only("Basics", async function () {
    const { account, accountContract, guardian } = await deployAccount(argentSessionAccountClassHash);

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

    let dappAccount = new Account(provider, account.address, sessionSigner);

    const outsideExecution: OutsideExecution = {
      caller: dappAccount.address,
      nonce: randomKeyPair().publicKey,
      execute_after: initialTime - 100,
      execute_before: initialTime + 100,
      calls: [getOutsideCall(testDapp.populateTransaction.set_number(42))],
    };
    const outsideExecutionCall = await getOutsideExecutionCallWithSession(
      outsideExecution,
      account.address,
      sessionSigner,
    );

    await setTime(initialTime);

    // normal scenario
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(true);

    await dappAccount.execute(outsideExecutionCall);

    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
    await accountContract.is_valid_outside_execution_nonce(outsideExecution.nonce).should.eventually.equal(false);

    // ensure a transaction can't be replayed
    await expectExecutionRevert("argent/duplicated-outside-nonce", () => dappAccount.execute(outsideExecutionCall));
  });
});
