import { Contract, typedData } from "starknet";
import {
  AllowedMethod,
  StarknetKeyPair,
  declareContract,
  deployAccount,
  deployer,
  loadContract,
  provider,
  setupSession,
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
    argentSessionAccountClassHash = await declareContract("ArgentAccount");
    const mockDappClassHash = await declareContract("MockDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: mockDappClassHash,
    });
    mockDapp = await loadContract(contract_address);
  });

  it("Basics: Revision 0", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: mockDappAccount } = await deployAccount();

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDapp.address,
        selector: "set_number",
      },
    ];

    const { dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const calls = [mockDapp.populateTransaction.set_number(42n)];

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      authorizationSignature,
      calls,
      legacyRevision,
      account.address,
      mockDappAccount.address,
    );

    await provider.setTime(initialTime);

    await mockDappAccount.execute(outsideExecutionCall);

    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });

  it("Basics: Revision 1", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: mockDappAccount } = await deployAccount();

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDapp.address,
        selector: "set_number",
      },
    ];

    const calls = [mockDapp.populateTransaction.set_number(42n)];

    const { dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      authorizationSignature,
      calls,
      activeRevision,
      account.address,
      mockDappAccount.address,
    );

    await provider.setTime(initialTime);

    await mockDappAccount.execute(outsideExecutionCall);

    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });
});
