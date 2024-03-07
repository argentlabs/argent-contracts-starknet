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
  getSessionTypedData,
} from "./lib";

const initialTime = 1713139200n;
describe("ArgentAccount: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentSessionAccountClassHash: string;
  let MockDapp: Contract;

  before(async () => {
    argentSessionAccountClassHash = await declareContract("ArgentAccount");
    const mockDappClassHash = await declareContract("MockDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: mockDappClassHash,
    });
    MockDapp = await loadContract(contract_address);
  });

  it("Basics", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: mockDappAccount } = await deployAccount();

    const backendService = new BackendService(guardian);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": MockDapp.address,
        selector: "set_number",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 1n);

    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    const calls = [MockDapp.populateTransaction.set_number(42n)];

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      accountSessionSignature,
      calls,
      account.address,
      mockDappAccount.address,
    );

    await setTime(initialTime);

    await mockDappAccount.execute(outsideExecutionCall);

    await MockDapp.get_number(account.address).should.eventually.equal(42n);
  });
});
