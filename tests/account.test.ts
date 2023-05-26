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
  randomPrivateKey,
  setTime,
} from "./lib";

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Deploy current version", async function () {
    const { accountContract, ownerPrivateKey } = await deployAccountWithoutGuardian(argentAccountClassHash);
    const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

    const owner = await accountContract.get_owner();
    expect(owner).to.equal(BigInt(ownerPublicKey));
    const guardian = await accountContract.get_guardian();
    expect(guardian).to.equal(0n);
    const guardianBackup = await accountContract.get_guardian_backup();
    expect(guardianBackup).to.equal(0n);
  });

  it("Deploy two accounts with the same owner", async function () {
    const privateKey = randomPrivateKey();
    const { accountContract: accountContract1 } = await deployAccountWithoutGuardian(
      argentAccountClassHash,
      privateKey,
    );
    const { accountContract: accountContract2 } = await deployAccountWithoutGuardian(
      argentAccountClassHash,
      privateKey,
    );
    const owner1 = await accountContract1.get_owner();
    const owner2 = await accountContract1.get_owner();
    expect(owner1).to.equal(owner2);
    expect(accountContract1.address != accountContract2.address).to.be.true;
  });

  it("Expect guardian backup to be 0 when deployed with an owner and a guardian", async function () {
    const { accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccount(argentAccountClassHash);
    const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);
    const guardianPublicKey = ec.starkCurve.getStarkKey(guardianPrivateKey as string);

    const owner = await accountContract.get_owner();
    expect(owner).to.equal(BigInt(ownerPublicKey));

    const guardian = await accountContract.get_guardian();
    expect(guardian).to.equal(BigInt(guardianPublicKey));

    const guardianBackup = await accountContract.get_guardian_backup();
    expect(guardianBackup).to.equal(0n);
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
    const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccount(
      argentAccountClassHash,
    );

    const guardianBackupBefore = await accountContract.get_guardian_backup();
    expect(guardianBackupBefore).to.equal(0n);
    account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
    await accountContract.change_guardian_backup(42);

    const guardianBackupAfter = await accountContract.get_guardian_backup();
    expect(guardianBackupAfter).to.equal(42n);
  });

  it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
    const guardianBackupPrivateKey = randomPrivateKey();
    const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey);
    const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccount(
      argentAccountClassHash,
    );

    const guardianBackupBefore = await accountContract.get_guardian_backup();
    expect(guardianBackupBefore).to.equal(0n);

    account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
    await accountContract.change_guardian_backup(guardianBackupPublicKey);

    const guardianBackupAfter = await accountContract.get_guardian_backup();
    expect(guardianBackupAfter).to.equal(BigInt(guardianBackupPublicKey));

    account.signer = new ArgentSigner(ownerPrivateKey, guardianBackupPrivateKey);
    await accountContract.change_guardian("0x42");

    const guardianAfter = await accountContract.get_guardian();
    expect(guardianAfter).to.equal(BigInt("0x42"));
  });

  it("Expect 'argent/invalid-signature-length' when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
    const { account, accountContract, ownerPrivateKey, guardianPrivateKey, guardianBackupPrivateKey } =
      await deployAccountWithGuardianBackup(argentAccountClassHash);

    account.signer = new ConcatSigner([
      ownerPrivateKey,
      guardianPrivateKey as string,
      guardianBackupPrivateKey as string,
    ]);

    await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
      accountContract.change_guardian("0x42"),
    );
  });

  describe("change_owner(new_owner, signature_r, signature_s)", function () {
    it("Should be possible to change_owner", async function () {
      const { accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);
      const newOwnerPrivateKey = randomPrivateKey();
      const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);
      const changeOwnerSelector = hash.getSelectorFromName("change_owner");
      const chainId = await provider.getChainId();
      const contractAddress = accountContract.address;
      const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

      const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
      const signature = ec.starkCurve.sign(msgHash, newOwnerPrivateKey);
      await accountContract.change_owner(newOwner, signature.r, signature.s);

      const owner_result = await accountContract.get_owner();
      expect(owner_result).to.equal(BigInt(newOwner));
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.change_owner(12, 13, 14));
    });

    it("Expect 'argent/null-owner' when new_owner is zero", async function () {
      const { accountContract } = await deployAccount(argentAccountClassHash);
      await expectRevertWithErrorMessage("argent/null-owner", () => accountContract.change_owner(0, 13, 14));
    });

    it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
      const { accountContract } = await deployAccount(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/invalid-owner-sig", () => accountContract.change_owner(11, 12, 42));
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccount(
        argentAccountClassHash,
      );

      const newOwnerPrivateKey = randomPrivateKey();
      const newOwner = BigInt(ec.starkCurve.getStarkKey(newOwnerPrivateKey));
      account.signer = new Signer(guardianPrivateKey);

      await setTime(42);
      await accountContract.trigger_escape_owner(newOwner);
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escape.ready_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(newOwner);
      await increaseTime(10);

      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      const changeOwnerSelector = hash.getSelectorFromName("change_owner");
      const chainId = await provider.getChainId();
      const contractAddress = accountContract.address;
      const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

      const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
      const signature = ec.starkCurve.sign(msgHash, newOwnerPrivateKey);
      await accountContract.change_owner(newOwner, signature.r, signature.s);

      const owner_result = await accountContract.get_owner();
      expect(owner_result).to.equal(BigInt(newOwner));

      const escapeReset = await accountContract.get_escape();
      expect(escapeReset.escape_type).to.equal(0n);
      expect(escapeReset.ready_at).to.equal(0n);
      expect(escapeReset.new_signer).to.equal(0n);
    });
  });
});
