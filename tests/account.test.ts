import { expect } from "chai";
import { CallData, Signer, ec, hash } from "starknet";
import {
  ArgentSigner,
  ConcatSigner,
  ESCAPE_SECURITY_PERIOD,
  ESCAPE_TYPE_OWNER,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployer,
  expectRevertWithErrorMessage,
  increaseTime,
  provider,
  randomKeyPair,
  setTime,
} from "./lib";

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Deploy current version", async function () {
    const { IAccount, owner } = await deployAccountWithoutGuardian(argentAccountClassHash);

    const ownerAddress = await IAccount.get_owner();
    expect(ownerAddress).to.equal(BigInt(owner.publicKey));
    const guardianAddress = await IAccount.get_guardian();
    expect(guardianAddress).to.equal(0n);
    const guardianBackupAddress = await IAccount.get_guardian_backup();
    expect(guardianBackupAddress).to.equal(0n);
  });

  it("Deploy two accounts with the same owner", async function () {
    const owner = randomKeyPair();
    const { IAccount: IAccount1 } = await deployAccountWithoutGuardian(argentAccountClassHash, owner);
    const { IAccount: IAccount2 } = await deployAccountWithoutGuardian(argentAccountClassHash, owner);
    const owner1 = await IAccount1.get_owner();
    const owner2 = await IAccount1.get_owner();
    expect(owner1).to.equal(owner2);
    expect(IAccount1.address != IAccount2.address).to.be.true;
  });

  it("Expect guardian backup to be 0 when deployed with an owner and a guardian", async function () {
    const { IAccount, owner, guardian } = await deployAccount(argentAccountClassHash);

    const ownerAddress = await IAccount.get_owner();
    expect(ownerAddress).to.equal(BigInt(owner.publicKey));

    const guardianAddress = await IAccount.get_guardian();
    expect(guardianAddress).to.equal(BigInt(guardian?.publicKey ?? 0n));

    const guardianBackupAddress = await IAccount.get_guardian_backup();
    expect(guardianBackupAddress).to.equal(0n);
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
    const { account, IAccount, owner, guardian } = await deployAccount(argentAccountClassHash);

    const guardianBackupBefore = await IAccount.get_guardian_backup();
    expect(guardianBackupBefore).to.equal(0n);
    account.signer = new ArgentSigner(owner.privateKey, guardian?.privateKey);
    await IAccount.change_guardian_backup(42);

    const guardianBackupAfter = await IAccount.get_guardian_backup();
    expect(guardianBackupAfter).to.equal(42n);
  });

  it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
    const guardianBackup = randomKeyPair();
    // const guardianBackupPrivateKey = randomPrivateKey();
    // const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey);
    const { account, IAccount, owner, guardian } = await deployAccount(argentAccountClassHash);

    const guardianBackupBefore = await IAccount.get_guardian_backup();
    expect(guardianBackupBefore).to.equal(0n);

    account.signer = new ArgentSigner(owner.privateKey, guardian?.privateKey);
    await IAccount.change_guardian_backup(guardianBackup.publicKey);

    const guardianBackupAfter = await IAccount.get_guardian_backup();
    expect(guardianBackupAfter).to.equal(BigInt(guardianBackup.publicKey));

    account.signer = new ArgentSigner(owner.privateKey, guardianBackup.privateKey);
    await IAccount.change_guardian("0x42");

    const guardianAfter = await IAccount.get_guardian();
    expect(guardianAfter).to.equal(BigInt("0x42"));
  });

  it("Expect 'argent/invalid-signature-length' when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
    const { account, IAccount, owner, guardian, guardianBackup } = await deployAccountWithGuardianBackup(
      argentAccountClassHash,
    );

    account.signer = new ConcatSigner([
      owner.privateKey,
      guardian?.privateKey as string,
      guardianBackup?.privateKey as string,
    ]);

    await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
      IAccount.change_guardian("0x42"),
    );
  });

  it("Should be impossible to call __validate__ from outside", async function () {
    const { IAccount } = await deployAccount(argentAccountClassHash);
    await expectRevertWithErrorMessage("argent/non-null-caller", () => IAccount.__validate__([]));
  });

  describe("change_owner(new_owner, signature_r, signature_s)", function () {
    it("Should be possible to change_owner", async function () {
      const { IAccount, owner } = await deployAccount(argentAccountClassHash);
      const newOwner = randomKeyPair();
      const changeOwnerSelector = hash.getSelectorFromName("change_owner");
      const chainId = await provider.getChainId();
      const contractAddress = IAccount.address;

      const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, owner.publicKey]);
      const signature = ec.starkCurve.sign(msgHash, newOwner.privateKey);
      await IAccount.change_owner(newOwner.publicKey, signature.r, signature.s);

      const owner_result = await IAccount.get_owner();
      expect(owner_result).to.equal(BigInt(newOwner.publicKey));
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { IAccount } = await deployAccount(argentAccountClassHash);
      IAccount.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => IAccount.change_owner(12, 13, 14));
    });

    it("Expect 'argent/null-owner' when new_owner is zero", async function () {
      const { IAccount } = await deployAccount(argentAccountClassHash);
      await expectRevertWithErrorMessage("argent/null-owner", () => IAccount.change_owner(0, 13, 14));
    });

    it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
      const { IAccount } = await deployAccount(argentAccountClassHash);
      await expectRevertWithErrorMessage("argent/invalid-owner-sig", () => IAccount.change_owner(11, 12, 42));
    });

    it("Expect the escape to be reset", async function () {
      const { account, IAccount, owner, guardian } = await deployAccount(argentAccountClassHash);

      const newOwner = randomKeyPair();
      account.signer = new Signer(guardian?.privateKey);

      await setTime(42);
      await IAccount.trigger_escape_owner(newOwner.publicKey);
      const escape = await IAccount.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escape.ready_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(BigInt(newOwner.publicKey));
      await increaseTime(10);

      account.signer = new ArgentSigner(owner.privateKey, guardian?.privateKey);
      const changeOwnerSelector = hash.getSelectorFromName("change_owner");
      const chainId = await provider.getChainId();
      const contractAddress = IAccount.address;
      const ownerPublicKey = ec.starkCurve.getStarkKey(owner.privateKey);

      const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
      const signature = ec.starkCurve.sign(msgHash, newOwner.privateKey);
      await IAccount.change_owner(newOwner.publicKey, signature.r, signature.s);

      const owner_result = await IAccount.get_owner();
      expect(owner_result).to.equal(BigInt(newOwner.publicKey));

      const escapeReset = await IAccount.get_escape();
      expect(escapeReset.escape_type).to.equal(0n);
      expect(escapeReset.ready_at).to.equal(0n);
      expect(escapeReset.new_signer).to.equal(0n);
    });
  });
});
