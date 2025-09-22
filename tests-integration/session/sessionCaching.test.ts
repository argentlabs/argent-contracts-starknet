import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData, Contract } from "starknet";
import {
  ArgentSigner,
  SignerType,
  StarknetKeyPair,
  deployAccount,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
  generateRandomNumber,
  manager,
  randomStarknetKeyPair,
  setupSession,
  signerTypeToCustomEnum,
  upgradeAccount,
} from "../../lib";
import { singleMethodAllowList } from "./sessionTestHelpers";

describe("Session Account: execute caching", function () {
  let argentAccountClassHash: string;
  let mockDappContract: Contract;
  let randomNumber: bigint;
  const initialTime = 1710167933n;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDappContract = await manager.declareAndDeployContract("MockDapp");
  });

  beforeEach(async function () {
    await manager.setTime(initialTime);
    randomNumber = generateRandomNumber();
  });

  for (const useCaching of [false, true]) {
    it(`Session is successfully cached when flag set (caching: ${useCaching})`, async function () {
      const { accountContract, account, guardian, owner } = await deployAccount({
        classHash: argentAccountClassHash,
      });

      const { accountWithDappSigner, sessionHash } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
      });
      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

      await accountContract.is_session_authorization_cached(sessionHash, owner.guid, guardian.guid).should.eventually.be
        .false;
      const { transaction_hash } = await accountWithDappSigner.execute(calls);

      await accountContract
        .is_session_authorization_cached(sessionHash, owner.guid, guardian.guid)
        .should.eventually.be.equal(useCaching);

      await account.waitForTransaction(transaction_hash);
      await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber);

      const calls2 = [mockDappContract.populateTransaction.set_number(randomNumber + 1n)];

      const { transaction_hash: tx2 } = await accountWithDappSigner.execute(calls2);

      await account.waitForTransaction(tx2);
      await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber + 1n);
    });

    it(`Fail with 'argent/invalid-signature-len' if more than owner + guardian signed session (caching: ${useCaching})`, async function () {
      const { account, guardian, accountContract, owner } = await deployAccount({ classHash: argentAccountClassHash });

      const { accountWithDappSigner, sessionHash, authorizationSignature, sessionRequest, dappService } =
        await setupSession({
          guardian: guardian as StarknetKeyPair,
          account,
          expiry: initialTime + 150n,
          dappKey: randomStarknetKeyPair(),
          cacheOwnerGuid: useCaching ? owner.guid : undefined,
          allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
        });

      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
      });
      sessionToken.sessionAuthorization = [...authorizationSignature, "0x0"];
      if (useCaching) {
        const { transaction_hash } = await accountWithDappSigner.execute(calls);
        await account.waitForTransaction(transaction_hash);
        await accountContract.is_session_authorization_cached(sessionHash, owner.guid, guardian.guid).should.eventually
          .be.true;
        await expectRevertWithErrorMessage(
          "session/cache-invalid-auth-len",
          executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
        );
      } else {
        await expectRevertWithErrorMessage(
          "argent/invalid-signature-len",
          executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
        );
      }
    });

    it(`Expect 'session/guardian-key-mismatch' if the backend signer != guardian (caching: ${useCaching})`, async function () {
      const { account, owner } = await deployAccount({ classHash: argentAccountClassHash });

      const { accountWithDappSigner } = await setupSession({
        guardian: randomStarknetKeyPair(),
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: owner.guid,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
      });

      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];
      await expectRevertWithErrorMessage("session/guardian-key-mismatch", accountWithDappSigner.execute(calls));
    });

    it(`Fail if a different dapp key signed session token (caching: ${useCaching})`, async function () {
      const { account, guardian, accountContract, owner } = await deployAccount({ classHash: argentAccountClassHash });

      const { accountWithDappSigner, sessionHash, sessionRequest, authorizationSignature, dappService } =
        await setupSession({
          guardian: guardian as StarknetKeyPair,
          account,
          expiry: initialTime + 150n,
          dappKey: randomStarknetKeyPair(),
          cacheOwnerGuid: owner.guid,
          allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
        });
      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
      });

      const originalSessionSignature = sessionToken.sessionSignature;
      sessionToken.sessionSignature = signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: 100n,
        r: originalSessionSignature.variant.Starknet.r,
        s: originalSessionSignature.variant.Starknet.s,
      });

      if (useCaching) {
        const { transaction_hash } = await accountWithDappSigner.execute(calls);
        await account.waitForTransaction(transaction_hash);
        await accountContract.is_session_authorization_cached(sessionHash, owner.guid, guardian.guid).should.eventually
          .be.true;
      }

      await expectRevertWithErrorMessage(
        "session/session-key-mismatch",
        executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
      );

      sessionToken.sessionSignature = signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: originalSessionSignature.variant.Starknet.pubkey,
        r: 200n,
        s: 100n,
      });

      await expectRevertWithErrorMessage(
        "session/invalid-session-sig",
        executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
      );
    });

    it(`Fail if a different guardian public key signed session token (caching: ${useCaching})`, async function () {
      const { account, guardian, owner } = await deployAccount({ classHash: argentAccountClassHash });

      const { accountWithDappSigner, sessionRequest, authorizationSignature, dappService } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: owner.guid,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
      });

      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];
      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
      });
      const originalGuardianSignature = sessionToken.guardianSignature;

      sessionToken.guardianSignature = signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: 100n,
        r: originalGuardianSignature.variant.Starknet.r,
        s: originalGuardianSignature.variant.Starknet.s,
      });

      await expectRevertWithErrorMessage(
        "session/guardian-key-mismatch",
        executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
      );
    });

    it(`Fail if a different guardian signature signed session token (caching: ${useCaching})`, async function () {
      const { account, guardian, owner } = await deployAccount({ classHash: argentAccountClassHash });

      const { accountWithDappSigner, sessionRequest, authorizationSignature, dappService } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: owner.guid,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
      });

      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
      });

      const originalGuardianSignature = sessionToken.guardianSignature;
      sessionToken.guardianSignature = signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: originalGuardianSignature.variant.Starknet.pubkey,
        r: 200n,
        s: 100n,
      });

      await expectRevertWithErrorMessage(
        "session/invalid-backend-sig",
        executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature(), { skipValidate: true }),
      );
    });
  }

  it("Invalidate Cache if owner that signed session is removed", async function () {
    const { account, guardian, owner, accountContract } = await deployAccount({ classHash: argentAccountClassHash });

    const newOwner = randomStarknetKeyPair();
    await accountContract.change_owners(
      CallData.compile({
        remove: [],
        add: [newOwner.signer],
        alive_signature: new CairoOption(CairoOptionVariant.None),
      }),
    );

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

    const { accountWithDappSigner, sessionHash } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      dappKey: randomStarknetKeyPair(),
      cacheOwnerGuid: owner.guid,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    await accountContract.is_session_authorization_cached(sessionHash, owner.guid, guardian.guid).should.eventually.be
      .false;
    const { transaction_hash } = await accountWithDappSigner.execute(calls);
    await account.waitForTransaction(transaction_hash);

    await accountContract
      .is_session_authorization_cached(sessionHash, owner.guid, guardian.guid)
      .should.eventually.be.equal(true);

    const signer = new ArgentSigner(newOwner, guardian);
    account.signer = signer;
    await accountContract.change_owners(
      CallData.compile({
        remove: [owner.guid],
        add: [],
        alive_signature: new CairoOption(CairoOptionVariant.None),
      }),
    );
    await accountContract.is_session_authorization_cached(sessionHash, owner.guid, guardian.guid).should.eventually.be
      .false;

    const calls2 = [mockDappContract.populateTransaction.set_number(randomNumber + 1n)];

    await expectRevertWithErrorMessage("session/cache-invalid-owner", accountWithDappSigner.execute(calls2));
  });

  it("Fail if a large authorization is injected", async function () {
    const { accountContract, account, guardian, owner } = await deployAccount();

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

    const { accountWithDappSigner, sessionHash, sessionRequest, dappService } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      dappKey: randomStarknetKeyPair(),
      cacheOwnerGuid: owner.guid,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const { transaction_hash } = await accountWithDappSigner.execute(calls);
    await account.waitForTransaction(transaction_hash);

    // check that the session is cached
    await accountContract.is_session_authorization_cached(sessionHash, owner.guid, guardian.guid).should.eventually.be
      .true;

    const sessionToken = await dappService.getSessionToken({
      calls,
      account: accountWithDappSigner,
      completedSession: sessionRequest,
      authorizationSignature: undefined,
      cacheOwnerGuid: owner.guid,
    });
    sessionToken.sessionAuthorization = Array(10).fill("1");
    await expectRevertWithErrorMessage(
      "session/cache-invalid-auth-len",
      executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
    );
  });

  it("Fail if a cache_owner_guid is incorrect", async function () {
    const { account, guardian } = await deployAccount();

    const { accountWithDappSigner } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      dappKey: randomStarknetKeyPair(),
      cacheOwnerGuid: 42n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    await expectRevertWithErrorMessage("session/owner-key-mismatch", accountWithDappSigner.execute([]));
  });

  describe("Session caching with legacy account", function () {
    it("Caching is unaffected between contract upgrades", async function () {
      const { account, accountContract, guardian, owner } = await deployAccount({
        classHash: await manager.declareArtifactAccountContract("0.4.0"),
      });
      const useCaching = true;
      const isLegacyAccount = true;

      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

      const { accountWithDappSigner, sessionHash } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
      });

      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.false;
      await accountWithDappSigner.execute(calls);
      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.equal(useCaching);
      await upgradeAccount(account, argentAccountClassHash);
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
      const newContract = await manager.loadContract(account.address, argentAccountClassHash);
      await newContract
        .is_session_authorization_cached(sessionHash, owner.guid, guardian.guid)
        .should.eventually.be.equal(useCaching);
    });

    it("Caching is unaffected between contract upgrades and if you add more owners", async function () {
      const { account, accountContract, guardian, owner } = await deployAccount({
        classHash: await manager.declareArtifactAccountContract("0.4.0"),
      });
      const useCaching = true;
      const isLegacyAccount = true;
      const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

      const { accountWithDappSigner, sessionHash } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
      });
      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.false;
      await accountWithDappSigner.execute(calls);
      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.equal(useCaching);
      await upgradeAccount(account, argentAccountClassHash);
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      const newContract = await manager.loadContract(account.address, argentAccountClassHash);

      newContract.connect(account);
      const newOwner = randomStarknetKeyPair();
      await newContract.change_owners(
        CallData.compile({
          remove: [],
          add: [newOwner.signer],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );
      await newContract
        .is_session_authorization_cached(sessionHash, owner.guid, guardian.guid)
        .should.eventually.be.equal(useCaching);
    });
  });
});
