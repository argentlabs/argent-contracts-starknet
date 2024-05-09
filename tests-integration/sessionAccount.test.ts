import { Contract, num } from "starknet";
import {
  AllowedMethod,
  ArgentX,
  BackendService,
  DappService,
  SignerType,
  StarknetKeyPair,
  compileSessionSignature,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployer,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
  getSessionTypedData,
  loadContract,
  provider,
  randomStarknetKeyPair,
  setupSession,
  signerTypeToCustomEnum,
} from "../lib";

describe("Hybrid Session Account: execute calls", function () {
  let sessionAccountClassHash: string;
  let mockDappContract: Contract;
  const initialTime = 1710167933n;

  before(async () => {
    sessionAccountClassHash = await declareContract("ArgentAccount");

    const mockDappClassHash = await declareContract("MockDapp");
    const deployedMockDapp = await deployer.deployContract({
      classHash: mockDappClassHash,
      salt: num.toHex(randomStarknetKeyPair().privateKey),
    });
    mockDappContract = await loadContract(deployedMockDapp.contract_address);
  });

  beforeEach(async function () {
    await provider.setTime(initialTime);
  });

  for (const useTxV3 of [false, true]) {
    it(`Execute basic session (TxV3: ${useTxV3})`, async function () {
      const { accountContract, account, guardian } = await deployAccount({
        useTxV3,
        classHash: sessionAccountClassHash,
      });

      const backendService = new BackendService(guardian as StarknetKeyPair);
      const dappService = new DappService(backendService);
      const argentX = new ArgentX(account, backendService);

      // Session creation:
      // 1. dapp request session: provides dapp pub key and policies
      const allowedMethods: AllowedMethod[] = [
        {
          "Contract Address": mockDappContract.address,
          selector: "set_number_double",
        },
      ];

      const sessionRequest = dappService.createSessionRequest(allowedMethods, initialTime + 150n);

      // 2. Owner and Guardian signs session
      const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

      //  Every request:
      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

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
      await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);
    });
  }

  it("Only execute tx if session not expired", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const expiresAt = initialTime + 60n * 24n;

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    // non expired session
    await provider.setTime(expiresAt - 10800n);
    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Expired session
    await provider.setTime(expiresAt + 7200n);
    await expectRevertWithErrorMessage("session/expired", () =>
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Revoke a session", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const { accountWithDappSigner, sessionHash } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Revoke Session
    await accountContract.revoke_session(sessionHash);
    await accountContract.is_session_revoked(sessionHash).should.eventually.be.true;
    await expectRevertWithErrorMessage("session/revoked", () =>
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

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
        "Contract Address": mockDappContract.address,
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

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

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
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    await expectRevertWithErrorMessage("session/signer-is-not-guardian", () => accountWithDappSigner.execute(calls));
  });

  it("Fail with 'argent/invalid-signature-len' if more than owner + guardian signed session", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    let sessionToken = await dappService.getSessionToken(
      calls,
      accountWithDappSigner,
      sessionRequest,
      authorizationSignature,
    );
    sessionToken = {
      ...sessionToken,
      session_authorization: [...sessionToken.session_authorization, "0x00"],
    };

    await expectRevertWithErrorMessage("argent/invalid-signature-len", () =>
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionToken)),
    );
  });

  it("Fail if a different dapp key signed session token", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const sessionToken = await dappService.getSessionToken(
      calls,
      accountWithDappSigner,
      sessionRequest,
      authorizationSignature,
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
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionTokenWrongPub)),
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
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionTokenWrongSig)),
    );
  });

  it("Fail if a different guardian key signed session token", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const sessionToken = await dappService.getSessionToken(
      calls,
      accountWithDappSigner,
      sessionRequest,
      authorizationSignature,
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
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionTokenWrongPub)),
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
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionTokenWrongSig)),
    );
  });

  it("Fail if proofs are misaligned", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_times3",
      },
      {
        "Contract Address": mockDappContract.address,
        selector: "increase_number",
      },
    ];

    const calls = [
      mockDappContract.populateTransaction.set_number_double(2),
      mockDappContract.populateTransaction.set_number_double(4),
      mockDappContract.populateTransaction.increase_number(2),
      mockDappContract.populateTransaction.increase_number(2),
    ];

    const { accountWithDappSigner, dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const sessionToken = await dappService.getSessionToken(
      calls,
      accountWithDappSigner,
      sessionRequest,
      authorizationSignature,
    );
    const sessionTokenWrongProofs = {
      ...sessionToken,
      proofs: [["0x2", "0x1"]],
    };

    await expectRevertWithErrorMessage("session/unaligned-proofs", () =>
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionTokenWrongProofs)),
    );
  });
});
