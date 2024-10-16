import { expect } from "chai";
import { CallData, Contract, num } from "starknet";
import {
  ArgentSigner,
  SignerType,
  StarknetKeyPair,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployer,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
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
  const initialTime = 1710167933n;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");

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
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });
      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.false;
      const { transaction_hash } = await accountWithDappSigner.execute(calls);

      await accountContract
        .is_session_authorization_cached(sessionHash, owner.guid)
        .should.eventually.be.equal(useCaching);

      await account.waitForTransaction(transaction_hash);
      await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

      const calls2 = [mockDappContract.populateTransaction.set_number_double(4)];

      const { transaction_hash: tx2 } = await accountWithDappSigner.execute(calls2);

      await account.waitForTransaction(tx2);
      await mockDappContract.get_number(accountContract.address).should.eventually.equal(8n);
    });
    it(`Fail if guardian backup signed session (caching: ${useCaching})`, async function () {
      const { account, guardian, owner } = await deployAccountWithGuardianBackup({
        classHash: argentAccountClassHash,
      });

      const { accountWithDappSigner } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });
      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      await expectRevertWithErrorMessage("session/signer-is-not-guardian", accountWithDappSigner.execute(calls));
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
          allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
        });

      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount: false,
      });
      sessionToken.sessionAuthorization = [...(sessionToken.sessionAuthorization ?? []), "0x0"];
      if (useCaching) {
        const { transaction_hash } = await accountWithDappSigner.execute(calls);
        await account.waitForTransaction(transaction_hash);
        await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.true;
        await expectRevertWithErrorMessage(
          "session/invalid-auth-len",
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
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });

      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      await expectRevertWithErrorMessage(
        "session/guardian-key-mismatch",
        accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
      );
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
          allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
        });
      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount: false,
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
        await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.true;
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

    it(`Fail if a different guardian key signed session token (caching: ${useCaching})`, async function () {
      const { account, guardian, owner } = await deployAccount({ classHash: argentAccountClassHash });

      const { accountWithDappSigner, sessionRequest, authorizationSignature, dappService } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: owner.guid,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });

      const calls = [mockDappContract.populateTransaction.set_number_double(2)];
      const sessionToken = await dappService.getSessionToken({
        calls,
        account: accountWithDappSigner,
        completedSession: sessionRequest,
        authorizationSignature,
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount: false,
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

      sessionToken.guardianSignature = signerTypeToCustomEnum(SignerType.Starknet, {
        pubkey: originalGuardianSignature.variant.Starknet.pubkey,
        r: 200n,
        s: 100n,
      });

      await expectRevertWithErrorMessage(
        "session/invalid-backend-sig",
        executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
      );
    });
  }

  it("Invalidate Cache if owner that signed session is removed", async function () {
    const { account, guardian, owner, accountContract } = await deployAccount({ classHash: argentAccountClassHash });

    const newOwner = randomStarknetKeyPair();
    const arrayOfSigner = CallData.compile({ new_owners: [newOwner.signer] });
    await accountContract.add_owners(arrayOfSigner);

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, sessionHash } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      dappKey: randomStarknetKeyPair(),
      cacheOwnerGuid: owner.guid,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
    });

    await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.false;
    const { transaction_hash } = await accountWithDappSigner.execute(calls);
    await account.waitForTransaction(transaction_hash);

    await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.equal(true);

    const signer = new ArgentSigner(newOwner, guardian);
    account.signer = signer;
    await accountContract.remove_owners([owner.guid]);
    await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.false;

    const calls2 = [mockDappContract.populateTransaction.set_number_double(4)];

    await expectRevertWithErrorMessage("session/signer-is-not-owner", accountWithDappSigner.execute(calls2));
  });
  it("Fail if a large authorization is injected", async function () {
    const { accountContract, account, guardian, owner } = await deployAccount({
      classHash: argentAccountClassHash,
    });

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner, sessionHash, sessionRequest, authorizationSignature, dappService } =
      await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: owner.guid,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });

    const { transaction_hash } = await accountWithDappSigner.execute(calls);
    await account.waitForTransaction(transaction_hash);

    // check that the session is cached
    await accountContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.true;

    const sessionToken = await dappService.getSessionToken({
      calls,
      account: accountWithDappSigner,
      completedSession: sessionRequest,
      authorizationSignature,
      cacheOwnerGuid: owner.guid,
      isLegacyAccount: false,
    });
    sessionToken.sessionAuthorization = Array(10).fill("1");
    await expectRevertWithErrorMessage(
      "session/invalid-auth-len",
      executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
    );
  });
  describe("Session caching with legacy account", function () {
    it("Caching is unaffected between contract upgrades", async function () {
      const { account, accountContract, guardian, owner } = await deployAccount({
        classHash: await manager.declareFixtureContract("ArgentAccount-0.4.0"),
      });
      const useCaching = true;
      const isLegacyAccount = true;

      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      const { accountWithDappSigner, sessionHash } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });

      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.false;
      await accountWithDappSigner.execute(calls);
      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.equal(useCaching);
      await upgradeAccount(account, argentAccountClassHash);
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
      const newContract = await manager.loadContract(account.address, argentAccountClassHash);
      await newContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.equal(useCaching);
    });
    it("Caching is unaffected between contract upgrades and if you add more owners", async function () {
      const { account, accountContract, guardian, owner } = await deployAccount({
        classHash: await manager.declareFixtureContract("ArgentAccount-0.4.0"),
      });
      const useCaching = true;
      const isLegacyAccount = true;
      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      const { accountWithDappSigner, sessionHash } = await setupSession({
        guardian: guardian as StarknetKeyPair,
        account,
        expiry: initialTime + 150n,
        dappKey: randomStarknetKeyPair(),
        cacheOwnerGuid: useCaching ? owner.guid : undefined,
        isLegacyAccount,
        allowedMethods: singleMethodAllowList(mockDappContract, "set_number_double"),
      });
      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.false;
      await accountWithDappSigner.execute(calls);
      await accountContract.is_session_authorization_cached(sessionHash).should.eventually.be.equal(useCaching);
      await upgradeAccount(account, argentAccountClassHash);
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      const newContract = await manager.loadContract(account.address, argentAccountClassHash);

      newContract.connect(account);
      const newOwner = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner.signer] });
      await newContract.add_owners(arrayOfSigner);
      await newContract.is_session_authorization_cached(sessionHash, owner.guid).should.eventually.be.equal(useCaching);
    });
  });
});
