import { CallData, Contract, num, typedData } from "starknet";
import {
  AllowedMethod,
  ArgentX,
  BackendService,
  DappService,
  SESSION_MAGIC,
  SignerType,
  StarknetKeyPair,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployer,
  expectRevertWithErrorMessage,
  getSessionTypedData,
  loadContract,
  randomStarknetKeyPair,
  setTime,
  setupSession,
  signerTypeToCustomEnum,
} from "../lib";

describe("Hybrid Session Account: execute calls", function () {
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

  it("Call a contract with backend signer", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian as StarknetKeyPair);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappOneContract.address,
        selector: "set_number_double",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 150n);

    // 2. Owner and Guardian signs session
    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    //  Every request:
    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Only execute tx if session not expired", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const expiresAt = initialTime + 60n * 24n;

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
    );
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    // non expired session
    await setTime(expiresAt - 10800n);
    await account.waitForTransaction(transaction_hash);
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Expired session
    await setTime(expiresAt + 7200n);
    await expectRevertWithErrorMessage("session/expired", () =>
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Revoke a session", async function () {
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

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const sessionHash = typedData.getMessageHash(await getSessionTypedData(sessionRequest), accountContract.address);

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Revoke Session
    await accountContract.revoke_session(sessionHash);
    await accountContract.is_session_revoked(sessionHash).should.eventually.be.true;
    await expectRevertWithErrorMessage("session/revoked", () =>
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
    await mockDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);

    await expectRevertWithErrorMessage("session/already-revoked", () => accountContract.revoke_session(sessionHash));
  });

  it("Expect 'session/guardian-key-mismatch' if the backend signer != guardian", async function () {
    const { account } = await deployAccount({ classHash: sessionAccountClassHash });

    // incorrect guardian
    const backendService = new BackendService(randomStarknetKeyPair());
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

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    await expectRevertWithErrorMessage("session/guardian-key-mismatch", () =>
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
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
    );

    await expectRevertWithErrorMessage("session/signer-is-not-guardian", () => accountWithDappSigner.execute(calls));
  });

  it("Fail with 'argent/invalid-signature-len' if more than owner + guardian signed session", async function () {
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

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const signerDetails = await accountWithDappSigner.getSignerDetails(calls);
    let sessionToken = await dappService.getRawSessionToken(
      calls,
      sessionRequest,
      accountSessionSignature,
      signerDetails,
    );
    sessionToken = {
      ...sessionToken,
      session_authorization: [...sessionToken.session_authorization, "0x00"],
    };

    await expectRevertWithErrorMessage("argent/invalid-signature-len", () =>
      accountWithDappSigner.executeWithCustomSig(calls, [SESSION_MAGIC, ...CallData.compile({ sessionToken })]),
    );
  });

  it("Fail if a different dapp key signed session token", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

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

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const signerDetails = await accountWithDappSigner.getSignerDetails(calls);
    const sessionToken = await dappService.getRawSessionToken(
      calls,
      sessionRequest,
      accountSessionSignature,
      signerDetails,
    );
    const sessionTokenWrongPub = {
      ...sessionToken,
      session_signature: signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: 100n,
        r: sessionToken.session_signature.variant.Starknet.r,
        s: sessionToken.session_signature.variant.Starknet.s,
      }),
    };

    await expectRevertWithErrorMessage("session/session-key-mismatch", () =>
      accountWithDappSigner.executeWithCustomSig(calls, [SESSION_MAGIC, ...CallData.compile({ sessionTokenWrongPub })]),
    );

    const sessionTokenWrongSig = {
      ...sessionToken,
      session_signature: signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: sessionToken.session_signature.variant.Starknet.pubkey,
        r: 200n,
        s: 100n,
      }),
    };

    await expectRevertWithErrorMessage("session/invalid-session-sig", () =>
      accountWithDappSigner.executeWithCustomSig(calls, [SESSION_MAGIC, ...CallData.compile({ sessionTokenWrongSig })]),
    );
  });

  it("Fail if a different guardian key signed session token", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

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

    const calls = [mockDappOneContract.populateTransaction.set_number_double(2)];

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const signerDetails = await accountWithDappSigner.getSignerDetails(calls);
    const sessionToken = await dappService.getRawSessionToken(
      calls,
      sessionRequest,
      accountSessionSignature,
      signerDetails,
    );
    const sessionTokenWrongPub = {
      ...sessionToken,
      guardian_signature: signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: 100n,
        r: sessionToken.guardian_signature.variant.Starknet.r,
        s: sessionToken.guardian_signature.variant.Starknet.s,
      }),
    };

    await expectRevertWithErrorMessage("session/guardian-key-mismatch", () =>
      accountWithDappSigner.executeWithCustomSig(calls, [SESSION_MAGIC, ...CallData.compile({ sessionTokenWrongPub })]),
    );

    const sessionTokenWrongSig = {
      ...sessionToken,
      guardian_signature: signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: sessionToken.guardian_signature.variant.Starknet.pubkey,
        r: 200n,
        s: 100n,
      }),
    };

    await expectRevertWithErrorMessage("session/invalid-backend-sig", () =>
      accountWithDappSigner.executeWithCustomSig(calls, [SESSION_MAGIC, ...CallData.compile({ sessionTokenWrongSig })]),
    );
  });

  it("Fail if proofs are misaligned", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian as StarknetKeyPair);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappOneContract.address,
        selector: "set_number_double",
      },
      {
        "Contract Address": mockDappOneContract.address,
        selector: "set_number_times3",
      },
      {
        "Contract Address": mockDappOneContract.address,
        selector: "increase_number",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 150n);

    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    const calls = [
      mockDappOneContract.populateTransaction.set_number_double(2),
      mockDappOneContract.populateTransaction.set_number_double(4),
      mockDappOneContract.populateTransaction.increase_number(2),
      mockDappOneContract.populateTransaction.increase_number(2),
    ];

    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const signerDetails = await accountWithDappSigner.getSignerDetails(calls);
    const sessionToken = await dappService.getRawSessionToken(
      calls,
      sessionRequest,
      accountSessionSignature,
      signerDetails,
    );
    const sessionTokenWrongProofs = {
      ...sessionToken,
      proofs: [["0x2", "0x1"]],
    };

    await expectRevertWithErrorMessage("session/unaligned-proofs", () =>
      accountWithDappSigner.executeWithCustomSig(calls, [
        SESSION_MAGIC,
        ...CallData.compile({ sessionTokenWrongProofs }),
      ]),
    );
  });
});
