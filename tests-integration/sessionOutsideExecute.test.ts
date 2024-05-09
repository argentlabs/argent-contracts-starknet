import { Contract, typedData } from "starknet";
import {
  AllowedMethod,
  ArgentX,
  BackendService,
  DappService,
  StarknetKeyPair,
  deployAccount,
  deployer,
  getSessionTypedData,
  manager,
} from "../lib";

const initialTime = 1713139200n;
const legacyRevision = typedData.TypedDataRevision.Legacy;
const activeRevision = typedData.TypedDataRevision.Active;
describe("ArgentAccount: outside execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentSessionAccountClassHash: string;
  let mockDapp: Contract;

  before(async () => {
    argentSessionAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    const mockDappClassHash = await manager.declareLocalContract("MockDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: mockDappClassHash,
    });
    mockDapp = await manager.loadContract(contract_address);
  });

  it("Basics: Revision 0", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: mockDappAccount } = await deployAccount();

    const backendService = new BackendService(guardian as StarknetKeyPair);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDapp.address,
        selector: "set_number",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 1n);

    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    const calls = [mockDapp.populateTransaction.set_number(42n)];

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      accountSessionSignature,
      calls,
      legacyRevision,
      account.address,
      mockDappAccount.address,
    );

    await manager.setTime(initialTime);

    await mockDappAccount.execute(outsideExecutionCall);

    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });

  it("Basics: Revision 1", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: mockDappAccount } = await deployAccount();

    const backendService = new BackendService(guardian as StarknetKeyPair);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDapp.address,
        selector: "set_number",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 1n);

    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    const calls = [mockDapp.populateTransaction.set_number(42n)];

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      accountSessionSignature,
      calls,
      activeRevision,
      account.address,
      mockDappAccount.address,
    );

    await manager.setTime(initialTime);

    await mockDappAccount.execute(outsideExecutionCall);

    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });
});
