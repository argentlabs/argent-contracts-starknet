import { expect } from "chai";
import { CallData } from "starknet";
import {
  ArgentSigner,
  ESCAPE_EXPIRY_PERIOD,
  ESCAPE_SECURITY_PERIOD,
  ESCAPE_TYPE_GUARDIAN,
  ESCAPE_TYPE_NONE,
  ESCAPE_TYPE_OWNER,
  EscapeStatus,
  KeyPair,
  LegacyArgentSigner,
  LegacyMultisigSigner,
  LegacyStarknetKeyPair,
  MAX_U64,
  StarknetKeyPair,
  deployAccount,
  deployAccountWithoutGuardians,
  deployOldAccountWithProxy,
  expectEvent,
  expectRevertWithErrorMessage,
  getEscapeStatus,
  hasOngoingEscape,
  manager,
  randomStarknetKeyPair,
  upgradeAccount,
  zeroStarknetSignatureType,
} from "../../lib";

describe("ArgentAccount: escape mechanism", function () {
  let argentAccountClassHash: string;
  let newKeyPair: KeyPair;
  let randomTime: bigint;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
  });

  beforeEach(async () => {
    newKeyPair = randomStarknetKeyPair();
    randomTime = BigInt(24 * 60 * 60) + BigInt(Math.floor(Math.random() * 1000));
  });

  describe("trigger_escape_owner(new_owner)", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage(
        "argent/only-self",
        accountContract.trigger_escape_owner(newKeyPair.compiledSigner),
      );
    });

    it("Expect parsing error when setting the new_owner to zero", async function () {
      const { account, accountContract, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      await expectRevertWithErrorMessage(
        "argent/invalid-calldata",
        accountContract.trigger_escape_owner(CallData.compile([zeroStarknetSignatureType()])),
      );
    });

    it("Expect 'argent/last-escape-too-recent' when trying to escape again too early", async function () {
      const { account, accountContract, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);

      await manager.setTime(randomTime + 12n * 60n * 60n);
      await expectRevertWithErrorMessage(
        "argent/last-escape-too-recent",
        accountContract.trigger_escape_owner(newKeyPair.compiledSigner),
      );
    });

    describe(`Triggered by guardian`, function () {
      it(`Expect to be able to trigger it alone`, async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        const readyAt = BigInt(randomTime) + ESCAPE_SECURITY_PERIOD;
        const response = await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);

        await accountContract
          .get_last_guardian_trigger_escape_attempt()
          .should.eventually.equal(roundDownToTheHour(randomTime));
        await accountContract.get_last_owner_trigger_escape_attempt().should.eventually.equal(0n);
        await accountContract.get_last_guardian_escape_attempt().should.eventually.equal(0n);
        await accountContract.get_last_owner_escape_attempt().should.eventually.equal(0n);

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_OWNER);
        expect(escape.ready_at).to.equal(readyAt);
        expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.NotReady);

        await expectEvent(response.transaction_hash, {
          from_address: account.address,
          eventName: "EscapeOwnerTriggeredGuid",
          data: [readyAt.toString(), newKeyPair.guid.toString()],
        });
      });

      it("Should be possible to escape_owner when a small escape security period is used", async function () {
        const { account, accountContract, guardian } = await deployAccount();

        await accountContract.set_escape_security_period(60 * 60); // 1h
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        await manager.setTime(randomTime + 60n * 60n);
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Ready);

        await accountContract.escape_owner();

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_NONE);
        expect(escape.ready_at).to.equal(0n);
        expect(escape.new_signer.isNone()).to.be.true;
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);
      });

      it("Expect 'argent/invalid-escape' when escaping too early when a small escape security period is used", async function () {
        const { account, accountContract, guardian } = await deployAccount();

        await accountContract.set_escape_security_period(60 * 60); // 1h
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        await manager.setTime(randomTime + 60n * 60n - 1n);

        await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_owner());
      });

      it(`Should be possible to use the legacy signature on trigger_escape_owner`, async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new LegacyArgentSigner(new LegacyStarknetKeyPair((guardian as StarknetKeyPair).privateKey));

        await manager.setTime(randomTime);
        const readyAt = BigInt(randomTime) + ESCAPE_SECURITY_PERIOD;
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_OWNER);
        expect(escape.ready_at).to.equal(readyAt);
        expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);
      });

      it(`Triggered by guardian. Expect 'argent/cannot-override-escape' when the owner is already being escaped`, async function () {
        const { account, accountContract, owner, guardian } = await deployAccount();
        account.signer = new ArgentSigner(owner);

        await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
        const { escape_type } = await accountContract.get_escape();
        expect(escape_type).to.deep.equal(ESCAPE_TYPE_GUARDIAN);

        account.signer = new ArgentSigner(guardian);
        await expectRevertWithErrorMessage(
          "argent/cannot-override-escape",
          accountContract.trigger_escape_owner(newKeyPair.compiledSigner),
        );
      });

      it("Expect to be able to trigger it alone when the previous escape expired", async function () {
        const { account, accountContract, owner, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        account.signer = new ArgentSigner(owner);
        await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_GUARDIAN);
        expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
        expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.NotReady);

        const randomKeyPair = randomStarknetKeyPair();
        account.signer = new ArgentSigner(guardian);
        await manager.setTime(randomTime + ESCAPE_EXPIRY_PERIOD);
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Expired);
        await accountContract.trigger_escape_owner(randomKeyPair.compiledSigner);
        const newEscape = await accountContract.get_escape();
        expect(newEscape.escape_type).to.deep.equal(ESCAPE_TYPE_OWNER);
        expect(newEscape.ready_at >= randomTime + ESCAPE_SECURITY_PERIOD + ESCAPE_EXPIRY_PERIOD).to.be.true;
        expect(newEscape.new_signer.unwrap().stored_value).to.equal(randomKeyPair.storedValue);
      });
    });

    it("Cancel owner escape by another owner escape", async function () {
      const { account, accountContract, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);
      const { compiledSigner } = randomStarknetKeyPair();

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_owner(compiledSigner);

      // increased time to prevent escape too recent error
      await manager.setTime(Number(randomTime) + 1 + 12 * 60 * 60 * 2);
      await expectEvent(() => accountContract.trigger_escape_owner(compiledSigner), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
    });
  });

  describe("escape_owner()", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", accountContract.escape_owner());
    });

    it("Cancel escape when upgrading", async function () {
      const { account, accountContract, owner, guardian } = await deployOldAccountWithProxy();
      account.signer = new LegacyMultisigSigner([guardian]);

      await manager.setTime(randomTime);
      await manager.waitForTx(accountContract.triggerEscapeSigner());

      account.signer = new LegacyMultisigSigner([owner, guardian]);
      const upgradeReceipt = await upgradeAccount(account, argentAccountClassHash, ["0"]);

      await expectEvent(upgradeReceipt.transaction_hash, {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
      await getEscapeStatus(await manager.loadContract(account.address)).should.eventually.equal(EscapeStatus.None);
    });

    it("Clear expired escape when upgrading", async function () {
      const { account, accountContract, owner, guardian } = await deployOldAccountWithProxy();
      account.signer = new LegacyMultisigSigner([guardian]);

      await manager.setTime(randomTime);
      await manager.waitForTx(accountContract.triggerEscapeSigner());

      await manager.setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);

      account.signer = new LegacyMultisigSigner([owner, guardian]);
      await upgradeAccount(account, argentAccountClassHash, ["0"]);
      await getEscapeStatus(await manager.loadContract(account.address)).should.eventually.equal(EscapeStatus.None);
    });

    describe(`Escaping by guardian`, function () {
      it("Expect to be able to escape the owner alone", async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Ready);

        const response = await accountContract.escape_owner();

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_NONE);
        expect(escape.ready_at).to.equal(0n);
        expect(escape.new_signer.isNone()).to.be.true;
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);

        await accountContract.get_owners_guids().should.eventually.deep.equal([newKeyPair.guid]);
        await expectEvent(response.transaction_hash, {
          from_address: account.address,
          eventName: "OwnerEscapedGuid",
          data: [newKeyPair.guid.toString()],
        });
      });

      it("Should be able to escape multiple owners", async function () {
        const { account, accountContract, guardian, owners } = await deployAccount({
          owners: Array.from({ length: 4 }, () => randomStarknetKeyPair()),
        });

        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);

        await accountContract.escape_owner();

        await accountContract.get_owners_guids().should.eventually.deep.equal([newKeyPair.guid]);
      });

      it("Should not be able to escape owners (keeping one owner)", async function () {
        const { account, accountContract, guardian, owners } = await deployAccount({
          owners: Array.from({ length: 4 }, () => randomStarknetKeyPair()),
        });
        account.signer = new ArgentSigner(guardian);
        const ownerToKeep = owners[0];
        await expectRevertWithErrorMessage(
          "argent/new-owner-is-owner",
          accountContract.trigger_escape_owner(ownerToKeep.compiledSigner),
        );
      });

      it("Should be possible to escape at max U64", async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        const endOfTime = MAX_U64 - ESCAPE_EXPIRY_PERIOD;
        await manager.setTime(endOfTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        await manager.setTime(endOfTime + ESCAPE_SECURITY_PERIOD);
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Ready);

        await accountContract.escape_owner();

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_NONE);
        expect(escape.ready_at).to.equal(0n);
        expect(escape.new_signer.isNone()).to.be.true;
        await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);

        await accountContract.get_owners_guids().should.eventually.deep.equal([newKeyPair.guid]);
      });

      it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        const { ready_at } = await accountContract.get_escape();
        expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

        await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
        await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_owner());
      });

      it("Expect 'argent/invalid-escape' when escape status == None", async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_owner());
      });

      it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
        const { account, accountContract, guardian } = await deployAccount();
        account.signer = new ArgentSigner(guardian);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
        const { ready_at } = await accountContract.get_escape();
        expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

        await manager.setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
        await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_owner());
      });

      it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_OWNER", async function () {
        const { account, accountContract, owner, guardian } = await deployAccount();
        account.signer = new ArgentSigner(owner);

        await manager.setTime(randomTime);
        await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_GUARDIAN);
        expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
        expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);

        await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);
        account.signer = new ArgentSigner(guardian);
        await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_owner());
      });
    });
  });

  describe("trigger_escape_guardian(new_guardian)", function () {
    it("Expect the owner to be able to trigger it alone", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      const readyAt = BigInt(randomTime) + ESCAPE_SECURITY_PERIOD;
      const response = await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);

      await accountContract.get_last_guardian_trigger_escape_attempt().should.eventually.equal(0n);
      await accountContract
        .get_last_owner_trigger_escape_attempt()
        .should.eventually.equal(roundDownToTheHour(randomTime));
      await accountContract.get_last_guardian_escape_attempt().should.eventually.equal(0n);
      await accountContract.get_last_owner_escape_attempt().should.eventually.equal(0n);

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escape.ready_at).to.equal(readyAt);
      expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);

      await expectEvent(response.transaction_hash, {
        from_address: account.address,
        eventName: "EscapeGuardianTriggeredGuid",
        data: [readyAt.toString(), newKeyPair.guid.toString()],
      });
    });

    it("Should be possible to escape_guardian when a small escape security period is used", async function () {
      const { account, accountContract, owner } = await deployAccount();

      await accountContract.set_escape_security_period(60 * 60); // 1h
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      await manager.setTime(randomTime + 60n * 60n);
      await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Ready);

      await accountContract.escape_guardian();

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_NONE);
      expect(escape.ready_at).to.equal(0n);
      expect(escape.new_signer.isNone()).to.be.true;
      await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);
    });

    it("Expect 'argent/invalid-escape' when escaping too early when a small escape security period is used", async function () {
      const { account, accountContract, owner } = await deployAccount();

      await accountContract.set_escape_security_period(60 * 60); // 1h
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      await manager.setTime(randomTime + 60n * 60n - 1n);

      await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_guardian());
    });

    it(`Should be possible to use the legacy signature on trigger_escape_guardian`, async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new LegacyArgentSigner(new LegacyStarknetKeyPair((owner as StarknetKeyPair).privateKey));

      await manager.setTime(randomTime);
      const readyAt = BigInt(randomTime) + ESCAPE_SECURITY_PERIOD;
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escape.ready_at).to.equal(readyAt);
      expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);
    });

    it("Expect 'argent/last-escape-too-recent' when trying too escape again too early", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);

      await manager.setTime(randomTime + 12n * 60n * 60n);
      await expectRevertWithErrorMessage(
        "argent/last-escape-too-recent",
        accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption),
      );
    });

    it("Expect the owner to be able to trigger_escape_guardian when trigger_escape_owner was performed", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);

      const escapeOwner = await accountContract.get_escape();
      expect(escapeOwner.escape_type).to.deep.equal(ESCAPE_TYPE_OWNER);
      expect(escapeOwner.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escapeOwner.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);

      // Let some block pass
      await manager.setTime(randomTime + 10n);
      const randomKeyPair = randomStarknetKeyPair();
      account.signer = new ArgentSigner(owner);
      const response = await accountContract.trigger_escape_guardian(randomKeyPair.compiledSignerAsOption);

      const escapeGuardian = await accountContract.get_escape();
      expect(escapeGuardian.escape_type).to.deep.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escapeGuardian.ready_at).to.be.equal(randomTime + ESCAPE_SECURITY_PERIOD + 10n);
      expect(escapeGuardian.new_signer.unwrap().stored_value).to.equal(randomKeyPair.storedValue);

      await expectEvent(response.transaction_hash, { from_address: account.address, eventName: "EscapeCanceled" });
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage(
        "argent/only-self",
        accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption),
      );
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { accountContract } = await deployAccountWithoutGuardians();

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      await expectRevertWithErrorMessage(
        "argent/guardian-required",
        accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption),
      );
    });
  });

  describe("escape_guardian()", function () {
    it("Expect the owner to be able to escape the guardian alone", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      const oldGuardian = await accountContract.get_guardian();
      expect(oldGuardian).to.equal(guardian.storedValue);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);

      const response = await accountContract.escape_guardian();

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_NONE);
      expect(escape.ready_at).to.equal(0n);
      expect(escape.new_signer.isNone()).to.be.true;
      const newGuardian = await accountContract.get_guardian();
      expect(newGuardian).to.equal(newKeyPair.storedValue);

      await expectEvent(response.transaction_hash, {
        from_address: account.address,
        eventName: "GuardianEscapedGuid",
        data: [newKeyPair.guid.toString()],
      });
    });

    it(`Should be possible to use the legacy signature on escape_guardian`, async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);

      account.signer = new LegacyArgentSigner(new LegacyStarknetKeyPair((owner as StarknetKeyPair).privateKey));
      await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      await accountContract.escape_guardian();

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_NONE);
      expect(escape.ready_at).to.equal(0n);
      expect(escape.new_signer.isNone()).to.be.true;
      const newGuardian = await accountContract.get_guardian();
      expect(newGuardian).to.equal(newKeyPair.storedValue);
    });

    it("Should be able to escape multiple guardians", async function () {
      const { account, accountContract, owner } = await deployAccount({
        guardians: Array.from({ length: 4 }, () => randomStarknetKeyPair()),
      });

      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);

      await accountContract.escape_guardian();

      await accountContract.get_guardians_guids().should.eventually.deep.equal([newKeyPair.guid]);
    });

    it("Should be able to escape guardians (keeping one guardian)", async function () {
      const { account, accountContract, owner, guardians } = await deployAccount({
        guardians: Array.from({ length: 4 }, () => randomStarknetKeyPair()),
      });

      account.signer = new ArgentSigner(owner);
      const guardianToKeep = guardians[0];
      await expectRevertWithErrorMessage(
        "argent/new-guardian-is-guardian",
        accountContract.trigger_escape_guardian(guardianToKeep.compiledSignerAsOption),
      );
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", accountContract.escape_guardian());
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { account, accountContract } = await deployAccountWithoutGuardians();

      await accountContract.get_guardian().should.eventually.equal(0n);

      await expectRevertWithErrorMessage(
        "argent/guardian-required",
        account.execute([accountContract.populateTransaction.escape_guardian()], undefined, { skipValidate: false }),
      );
    });

    it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      const { ready_at } = await accountContract.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == None", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      const { ready_at } = await accountContract.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await manager.setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_GUARDIAN", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.deep.equal(ESCAPE_TYPE_OWNER);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer.unwrap().stored_value).to.equal(newKeyPair.storedValue);

      await manager.setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.signer = new ArgentSigner(owner);
      await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.escape_guardian());
    });
  });

  describe("cancel_escape()", function () {
    it("Expect the escape to be canceled when trigger_escape_owner", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);
      await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      account.signer = new ArgentSigner(owner, guardian);
      await expectEvent(() => accountContract.cancel_escape(), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });

      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect the escape to be canceled when trigger_escape_guardian", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(owner);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect the escape to be canceled even if expired", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await manager.setTime(randomTime);
      await accountContract.trigger_escape_guardian(newKeyPair.compiledSignerAsOption);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      await manager.setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
      account.signer = new ArgentSigner(owner, guardian);
      await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Expired);

      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect the escape to be canceled by another guardian when trigger_escape_owner", async function () {
      const { account, accountContract, owner, guardians } = await deployAccount({
        guardians: Array.from({ length: 4 }, () => randomStarknetKeyPair()),
      });
      account.signer = new ArgentSigner(guardians[0]);
      await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      account.signer = new ArgentSigner(owner, guardians[1]);
      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect the escape to be canceled by another owner when trigger_escape_owner", async function () {
      const { account, accountContract, guardian, owners } = await deployAccount({
        owners: Array.from({ length: 4 }, () => randomStarknetKeyPair()),
      });
      account.signer = new ArgentSigner(guardian);
      await accountContract.trigger_escape_owner(newKeyPair.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      account.signer = new ArgentSigner(owners[1], guardian);
      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", accountContract.cancel_escape());
    });

    it("Expect 'argent/invalid-escape' when escape == None", async function () {
      const { accountContract } = await deployAccount();
      await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);
      await expectRevertWithErrorMessage("argent/invalid-escape", accountContract.cancel_escape());
    });
  });
});

function roundDownToTheHour(timeInSeconds: bigint): bigint {
  const timeInHours = timeInSeconds / 3600n;
  const roundedHours = Math.floor(Number(timeInHours));
  return BigInt(roundedHours) * 3600n;
}
