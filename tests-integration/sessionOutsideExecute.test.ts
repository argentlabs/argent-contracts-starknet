import { Contract, selector } from "starknet";
import {
  declareContract,
  deployAccount,
  deployer,
  loadContract,
  setTime,
  BackendService,
  DappService,
  ArgentX,
  AllowedMethod,
  TokenAmount,
  SessionSigner,
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

  it("Basics", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: testDappAccount } = await deployAccount();

    const backendService = new BackendService(guardian);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": testDapp.address,
        selector: selector.getSelectorFromName("set_number"),
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, tokenAmounts);

    const accountSessionSignature = await argentX.getOffchainSignature(sessionRequest);

    const sessionSigner = new SessionSigner(
      backendService,
      dappService.sessionKey,
      accountSessionSignature,
      sessionRequest,
    );

    const calls = [testDapp.populateTransaction.set_number(42n)];

    const outsideExecutionCall = await sessionSigner.getOutisdeExecutionCall(calls, account.address);

    await setTime(initialTime);

    await testDappAccount.execute(outsideExecutionCall);

    await testDapp.get_number(account.address).should.eventually.equal(42n, "invalid new value");
  });
});
