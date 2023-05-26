import { expect } from "chai";
import { CallData, ec, hash } from "starknet";
import {
  ArgentSigner,
  ConcatSigner,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployer,
  expectRevertWithErrorMessage,
  provider,
  randomPrivateKey,
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

  it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
    const { accountContract } = await deployAccount(argentAccountClassHash);
    const newOwnerPrivateKey = randomPrivateKey();
    const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);

    await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
      accountContract.change_owner(newOwner, "12", "42"),
    );
  });

  it("Should be possible to change_owner", async function () {
    const { account, accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);
    const newOwnerPrivateKey = randomPrivateKey();
    const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);
    const changeOwnerSelector = hash.getSelectorFromName("change_owner");
    const chainId = await provider.getChainId();
    const contractAddress = account.address;
    const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

    const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
    const signature = ec.starkCurve.sign(msgHash, newOwnerPrivateKey);
    await accountContract.change_owner(newOwner, signature.r, signature.s);

    const owner_result = await accountContract.get_owner();
    expect(owner_result).to.equal(BigInt(newOwner));
  });

  it("Should be impossible to call __validate__ from outside", async function () {
    const { accountContract } = await deployAccount(argentAccountClassHash);
    await expectRevertWithErrorMessage("argent/non-null-caller", () => accountContract.__validate__([]));
  });
});
