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
  provider,
  randomKeyPair,
} from "./lib";

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Deploy current version", async function () {
    const { accountContract, owner } = await deployAccountWithoutGuardian(argentAccountClassHash);

    const ownerAddress = await accountContract.get_owner();
    expect(ownerAddress).to.equal(owner.publicKey);
    const guardianAddress = await accountContract.get_guardian();
    expect(guardianAddress).to.equal(0n);
    const guardianBackupAddress = await accountContract.get_guardian_backup();
    expect(guardianBackupAddress).to.equal(0n);
  });

  it("Deploy two accounts with the same owner", async function () {
    const owner = randomKeyPair();
    const { accountContract: accountContract1 } = await deployAccountWithoutGuardian(argentAccountClassHash, owner);
    const { accountContract: accountContract2 } = await deployAccountWithoutGuardian(argentAccountClassHash, owner);
    const owner1 = await accountContract1.get_owner();
    const owner2 = await accountContract1.get_owner();
    expect(owner1).to.equal(owner2);
    expect(accountContract1.address != accountContract2.address).to.be.true;
  });

  it("Expect guardian backup to be 0 when deployed with an owner and a guardian", async function () {
    const { accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);

    const ownerAddress = await accountContract.get_owner();
    expect(ownerAddress).to.equal(owner.publicKey);

    const guardianAddress = await accountContract.get_guardian();
    expect(guardianAddress).to.equal(guardian?.publicKey ?? 0n);

    const guardianBackupAddress = await accountContract.get_guardian_backup();
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
    const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);

    const guardianBackupBefore = await accountContract.get_guardian_backup();
    expect(guardianBackupBefore).to.equal(0n);
    account.signer = new ArgentSigner(owner, guardian);
    await accountContract.change_guardian_backup(42);

    const guardianBackupAfter = await accountContract.get_guardian_backup();
    expect(guardianBackupAfter).to.equal(42n);
  });

  it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
    const guardianBackup = randomKeyPair();
    const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);

    const guardianBackupBefore = await accountContract.get_guardian_backup();
    expect(guardianBackupBefore).to.equal(0n);

    account.signer = new ArgentSigner(owner, guardian);
    await accountContract.change_guardian_backup(guardianBackup.publicKey);

    const guardianBackupAfter = await accountContract.get_guardian_backup();
    expect(guardianBackupAfter).to.equal(guardianBackup.publicKey);

    account.signer = new ArgentSigner(owner, guardianBackup);
    await accountContract.change_guardian("0x42");

    const guardianAfter = await accountContract.get_guardian();
    expect(guardianAfter).to.equal(BigInt("0x42"));
  });

  it("Expect 'argent/invalid-signature-length' when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
    const { account, accountContract, owner, guardian, guardianBackup } = await deployAccountWithGuardianBackup(
      argentAccountClassHash,
    );

    account.signer = new ConcatSigner([owner, guardian, guardianBackup]);

    await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
      accountContract.change_guardian("0x42"),
    );
  });

  it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
    const { accountContract } = await deployAccount(argentAccountClassHash);
    await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
      accountContract.change_owner(randomKeyPair().publicKey, "12", "42"),
    );
  });

  it("Should be possible to change_owner", async function () {
    const { account, accountContract, owner } = await deployAccount(argentAccountClassHash);
    const newOwner = randomKeyPair();
    const changeOwnerSelector = hash.getSelectorFromName("change_owner");
    const chainId = await provider.getChainId();
    const contractAddress = account.address;

    const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, owner.publicKey]);
    const signature = newOwner.signHash(msgHash);
    await accountContract.change_owner(newOwner.publicKey, signature.r, signature.s);

    const ownerResult = await accountContract.get_owner();
    expect(ownerResult).to.equal(newOwner.publicKey);
  });

  it("Should be impossible to call __validate__ from outside", async function () {
    const { accountContract } = await deployAccount(argentAccountClassHash);
    await expectRevertWithErrorMessage("argent/non-null-caller", () => accountContract.__validate__([]));
  });
});
