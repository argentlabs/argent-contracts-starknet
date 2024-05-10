import { Contract, num } from "starknet";
import {
  AllowedMethod,
  StarknetKeyPair,
  compileSessionSignature,
  deployAccount,
  deployer,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
  manager,
  randomStarknetKeyPair,
  setupSession,
} from "../lib";

describe("Hybrid Session Account: execute session calls with caching", function () {
  let sessionAccountClassHash: string;
  let mockDappContract: Contract;
  const initialTime = 1710167933n;

  before(async () => {
    sessionAccountClassHash = await manager.declareLocalContract("ArgentAccount");

    const mockDappClassHash = await manager.declareLocalContract("MockDapp");
    const deployedMockDapp = await deployer.deployContract({
      classHash: mockDappClassHash,
      salt: num.toHex(randomStarknetKeyPair().privateKey),
    });
    mockDappContract = await manager.loadContract(deployedMockDapp.contract_address);
  });

  beforeEach(async function () {
    await manager.setTime(initialTime);
  });

  it("Use Session with caching enabled", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, sessionHash } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
      randomStarknetKeyPair(),
      true,
    );

    await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.false;
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

    // check that the session is cached
    await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.true;

    const calls2 = [mockDappContract.populateTransaction.set_number_double(4)];

    const { transaction_hash: tx2 } = await accountWithDappSigner.execute(calls2);

    await account.waitForTransaction(tx2);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(8n);
  });

  it("Fail if a large authorization is injected", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, dappService, sessionRequest, authorizationSignature, sessionHash } =
      await setupSession(
        guardian as StarknetKeyPair,
        account,
        allowedMethods,
        initialTime + 150n,
        randomStarknetKeyPair(),
        true,
      );
    const { transaction_hash } = await accountWithDappSigner.execute(calls);
    await account.waitForTransaction(transaction_hash);

    // check that the session is cached
    await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.true;

    let sessionToken = await dappService.getSessionToken(
      calls,
      accountWithDappSigner,
      sessionRequest,
      authorizationSignature,
      true,
    );
    sessionToken = {
      ...sessionToken,
      session_authorization: Array(10)
        .fill(null)
        .map(() => "1"),
    };
    await expectRevertWithErrorMessage("session/invalid-auth-len", () =>
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionToken)),
    );
  });
});
