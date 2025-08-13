import { Contract, TypedDataRevision } from "starknet";
import { StarknetKeyPair, deployAccount, manager, setupSession } from "../../lib";
import { singleMethodAllowList } from "./sessionTestHelpers";

const initialTime = 1713139200n;
const legacyRevision = TypedDataRevision.LEGACY;
const activeRevision = TypedDataRevision.ACTIVE;
describe("ArgentAccount: session outside execution", function () {
  let argentSessionAccountClassHash: string;
  let mockDapp: Contract;

  before(async () => {
    argentSessionAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.declareAndDeployContract("MockDapp");
  });

  it("Basics: Revision 0", async function () {
    const { account, guardian } = await deployAccount({ classHash: argentSessionAccountClassHash });

    const { account: mockDappAccount } = await deployAccount();

    const { sessionRequest, authorizationSignature, dappService } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDapp, "set_number"),
    });

    const calls = [mockDapp.populateTransaction.set_number(42n)];

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      authorizationSignature,
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

    const calls = [mockDapp.populateTransaction.set_number(42n)];

    const { sessionRequest, authorizationSignature, dappService } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDapp, "set_number"),
    });

    const outsideExecutionCall = await dappService.getOutsideExecutionCall(
      sessionRequest,
      authorizationSignature,
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
