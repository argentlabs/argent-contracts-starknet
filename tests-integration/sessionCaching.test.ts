import { CallData, Contract, num, typedData } from "starknet";
import {
  AllowedMethod,
  ArgentX,
  BackendService,
  DappService,
  SESSION_MAGIC,
  StarknetKeyPair,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployer,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
  getSessionTypedData,
  loadContract,
  randomStarknetKeyPair,
  setTime,
  setupSession,
} from "../lib";

describe("Hybrid Session Account: execute session calls with caching", function () {
  let sessionAccountClassHash: string;
  let mockDappOneContract: Contract;
  const initialTime = 1710167933n;

  before(async () => {
    sessionAccountClassHash = await declareContract("ArgentAccount");

    const mockDappClassHash = await declareContract("MockDapp");
    const deployedmockDappOne = await deployer.deployContract({
      classHash: mockDappClassHash,
      salt: num.toHex(randomStarknetKeyPair().privateKey),
    });
    mockDappOneContract = await loadContract(deployedmockDappOne.contract_address);
  });

  beforeEach(async function () {
    await setTime(initialTime);
  });

  it("Use Session with caching enabled", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian as StarknetKeyPair);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappOneContract.address,
        selector: "set_number_double",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 150n);

    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    const sessionHash = typedData.getMessageHash(await getSessionTypedData(sessionRequest), accountContract.address);

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
      true,
    );

    await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.false;
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);

    // check that the session is cached
    await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.true;

    const calls2 = [mockDappOneContract.populateTransaction.set_number_double(4)];

    const { transaction_hash: tx2 } = await accountWithDappSigner.execute(calls2);

    await account.waitForTransaction(tx2);
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(8n);
  });

  it("Fail if guardian backup signed session", async function () {
    const { account, guardian } = await deployAccountWithGuardianBackup({
      classHash: sessionAccountClassHash,
    });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappOneContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const accountWithDappSigner = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
      randomStarknetKeyPair(),
      true,
    );

    await expectRevertWithErrorMessage("session/signer-is-not-guardian", () => accountWithDappSigner.execute(calls));
  });

  it("Fail if a large authorization is injected", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian as StarknetKeyPair);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappOneContract.address,
        selector: "set_number_double",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 150n);

    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    const sessionHash = typedData.getMessageHash(await getSessionTypedData(sessionRequest), accountContract.address);

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
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
      accountSessionSignature,
      true,
    );
    sessionToken = {
      ...sessionToken,
      session_authorization: Array(10)
        .fill(null)
        .map(() => "1"),
    };
    await expectRevertWithErrorMessage("session/invalid-auth-len", () =>
      executeWithCustomSig(accountWithDappSigner, calls, [SESSION_MAGIC, ...CallData.compile({ sessionToken })]),
    );
  });
});
