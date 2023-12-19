import { expect } from "chai";
import { CallData, hash } from "starknet";
import {
  ArgentSigner,
  ConcatSigner,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployer,
  expectRevertWithErrorMessage,
  hasOngoingEscape,
  increaseTime,
  provider,
  randomKeyPair,
  signChangeOwnerMessage,
  restartDevnetIfTooLong,
} from "./lib";

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    await restartDevnetIfTooLong();
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Deploy externally", async function () {
    const { accountContract, owner } = await deployAccountWithoutGuardian({ fundingAmount: 0, selfDeploy: false });

    await accountContract.get_owner().should.eventually.equal(owner.publicKey);
    await accountContract.get_guardian().should.eventually.equal(0n);
    await accountContract.get_guardian_backup().should.eventually.equal(0n);
  });

  it("Self deployment", async function () {
    const { accountContract, owner } = await deployAccountWithoutGuardian({ selfDeploy: true });

    await accountContract.get_owner().should.eventually.equal(owner.publicKey);
    await accountContract.get_guardian().should.eventually.equal(0n);
    await accountContract.get_guardian_backup().should.eventually.equal(0n);
  });

  it("Deploy two accounts with the same owner", async function () {
    const owner = randomKeyPair();
    const { accountContract: accountContract1 } = await deployAccountWithoutGuardian({ owner });
    const { accountContract: accountContract2 } = await deployAccountWithoutGuardian({ owner });
    const owner1 = await accountContract1.get_owner();
    const owner2 = await accountContract1.get_owner();
    expect(owner1).to.equal(owner2);
    expect(accountContract1.address != accountContract2.address).to.be.true;
  });

  it("Expect guardian backup to be 0 when deployed with an owner and a guardian", async function () {
    const { accountContract, owner, guardian } = await deployAccount();

    await accountContract.get_owner().should.eventually.equal(owner.publicKey);
    await accountContract.get_guardian().should.eventually.equal(guardian.publicKey);
    await accountContract.get_guardian_backup().should.eventually.equal(0n);
  });

  it("Expect an error when owner is zero", async function () {
    await expectRevertWithErrorMessage("argent/null-owner", () =>
      deployer.deployContract({
        classHash: argentAccountClassHash,
        constructorCalldata: CallData.compile({ owner: 0, guardian: 12 }),
      }),
    );
  });

  it("Should use signature from BOTH OWNER and GUARDIAN when there is a GUARDIAN", async function () {
    const { account, accountContract, owner, guardian } = await deployAccount();

    await accountContract.get_guardian_backup().should.eventually.equal(0n);
    account.signer = new ArgentSigner(owner, guardian);
    await accountContract.change_guardian_backup(42);

    await accountContract.get_guardian_backup().should.eventually.equal(42n);
  });

  it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
    const guardianBackup = randomKeyPair();
    const { account, accountContract, owner, guardian } = await deployAccount();

    await accountContract.get_guardian_backup().should.eventually.equal(0n);

    account.signer = new ArgentSigner(owner, guardian);
    await accountContract.change_guardian_backup(guardianBackup.publicKey);

    await accountContract.get_guardian_backup().should.eventually.equal(guardianBackup.publicKey);

    account.signer = new ArgentSigner(owner, guardianBackup);
    await accountContract.change_guardian(42n);

    await accountContract.get_guardian().should.eventually.equal(42n);
  });

  it("Expect 'argent/invalid-signature-length' when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
    const { account, accountContract, owner, guardian, guardianBackup } = await deployAccountWithGuardianBackup();

    account.signer = new ConcatSigner([owner, guardian, guardianBackup]);

    await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
      accountContract.change_guardian("0x42"),
    );
  });

  it("Should be impossible to call __validate__ from outside", async function () {
    const { accountContract } = await deployAccount();
    await expectRevertWithErrorMessage("argent/non-null-caller", () => accountContract.__validate__([]));
  });

  describe("change_owner(new_owner, signature_r, signature_s)", function () {
    it("Should be possible to change_owner", async function () {
      const { accountContract, owner } = await deployAccount();
      const newOwner = randomKeyPair();

      const chainId = await provider.getChainId();
      const [r, s] = await signChangeOwnerMessage(accountContract.address, owner.publicKey, newOwner, chainId);
      await accountContract.change_owner(newOwner.publicKey, r, s);

      await accountContract.get_owner().should.eventually.equal(newOwner.publicKey);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.change_owner(12, 13, 14));
    });

    it("Expect 'argent/null-owner' when new_owner is zero", async function () {
      const { accountContract } = await deployAccount();
      await expectRevertWithErrorMessage("argent/null-owner", () => accountContract.change_owner(0, 13, 14));
    });

    it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
      const { accountContract } = await deployAccount();
      await expectRevertWithErrorMessage("argent/invalid-owner-sig", () => accountContract.change_owner(11, 12, 42));
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount({ useTxV3: true });

      const newOwner = randomKeyPair();
      account.signer = guardian;

      await accountContract.trigger_escape_owner(newOwner.publicKey);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      const chainId = await provider.getChainId();
      const [r, s] = await signChangeOwnerMessage(accountContract.address, owner.publicKey, newOwner, chainId);

      await accountContract.change_owner(newOwner.publicKey, r, s);

      await accountContract.get_owner().should.eventually.equal(newOwner.publicKey);
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  describe("change_guardian(new_guardian)", function () {
    it("Should be possible to change_guardian", async function () {
      const { accountContract } = await deployAccount();
      const newGuardian = 12n;
      await accountContract.change_guardian(newGuardian);

      await accountContract.get_guardian().should.eventually.equal(newGuardian);
    });

    it("Should be possible to change_guardian to zero when there is no backup", async function () {
      const { accountContract } = await deployAccount();
      await accountContract.change_guardian(0);

      await accountContract.get_guardian_backup().should.eventually.equal(0n);
      await accountContract.get_guardian().should.eventually.equal(0n);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.change_guardian(12));
    });

    it("Expect 'argent/backup-should-be-null' when setting the guardian to 0 if there is a backup", async function () {
      const { accountContract } = await deployAccountWithGuardianBackup();
      await accountContract.get_guardian_backup().should.eventually.not.equal(0n);
      await expectRevertWithErrorMessage("argent/backup-should-be-null", () => accountContract.change_guardian(0));
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = guardian;

      const newOwner = randomKeyPair();
      const newGuardian = 12n;

      await accountContract.trigger_escape_owner(newOwner.publicKey);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.change_guardian(newGuardian);

      await accountContract.get_guardian().should.eventually.equal(newGuardian);
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  describe("change_guardian_backup(new_guardian)", function () {
    it("Should be possible to change_guardian_backup", async function () {
      const { accountContract } = await deployAccountWithGuardianBackup();
      const newGuardianBackup = 12n;
      await accountContract.change_guardian_backup(newGuardianBackup);

      await accountContract.get_guardian_backup().should.eventually.equal(newGuardianBackup);
    });

    it("Should be possible to change_guardian_backup to zero", async function () {
      const { accountContract } = await deployAccountWithGuardianBackup();
      await accountContract.change_guardian_backup(0);

      await accountContract.get_guardian_backup().should.eventually.equal(0n);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.change_guardian_backup(12));
    });

    it("Expect 'argent/guardian-required' when guardian == 0 and setting a guardian backup ", async function () {
      const { accountContract } = await deployAccountWithoutGuardian();
      await accountContract.get_guardian().should.eventually.equal(0n);
      await expectRevertWithErrorMessage("argent/guardian-required", () => accountContract.change_guardian_backup(12));
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccountWithGuardianBackup();

      const newOwner = randomKeyPair();
      account.signer = guardian;
      const newGuardian = 12n;

      await accountContract.trigger_escape_owner(newOwner.publicKey);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.change_guardian_backup(newGuardian);

      await accountContract.get_guardian_backup().should.eventually.equal(newGuardian);
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  it("Expect 'Entry point X not found' when calling the constructor", async function () {
    const { account } = await deployAccount();
    try {
      const { transaction_hash } = await account.execute({
        contractAddress: account.address,
        entrypoint: "constructor",
        calldata: CallData.compile({ owner: 12, guardian: 13 }),
      });
      await provider.waitForTransaction(transaction_hash);
    } catch (e: any) {
      expect(e.toString()).to.contain(
        `Entry point EntryPointSelector(StarkFelt(\\"0x028ffe4ff0f226a9107253e17a904099aa4f63a02a5621de0576e5aa71bc5194\\")) not found in contract`,
      );
    }
  });
});
