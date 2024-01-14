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
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    argentSessionAccountClassHash = await declareContract("HybridSessionAccount");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it.only("Basics", async function () {
    const { account, guardian } = await deployAccount(argentSessionAccountClassHash);

    const { account: testDappAccount } = await deployAccount(argentAccountClassHash);

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
    const accountSessionSignature = await argentX.getOffchainSignature(sessionRequest);

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const sessionSigner = new SessionSigner(
      backendService,
      dappService.keypair,
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
