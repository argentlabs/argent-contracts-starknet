import { expect } from "chai";
import { CallData, ec, hash, stark } from "starknet";
import {
  ArgentSigner,
  ConcatSigner,
  declareContract,
  deployAccount,
  deployerAccount,
  expectRevertWithErrorMessage,
  loadContract,
  provider,
} from "./shared";

describe("ArgentAccount", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  beforeEach(async () => {
    // TODO When everything is more clean, we could deploy a new funded cairo1 account and use that one to do all the logic
    // TODO We could dump and load, instead of redeploying an account each time
    // TODO we could do a fastContract with maxFee to have faster tests
  });

  describe("Example tests", function () {
    it("Expect guardian and guardian backup to be 0 when deployed with an owner only", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account.address);

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      const guardianBackup = await accountContract.get_guardian_backup();
      expect(guardianBackup).to.equal(0n);
    });

    it("Expect guardian backup to be 0 when deployed with an owner and a guardian", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);
      const guardianPrivateKey = stark.randomAddress();
      const guardianPublicKey = ec.starkCurve.getStarkKey(guardianPrivateKey);
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      const owner = await accountContract.get_owner();
      expect(owner).to.equal(BigInt(ownerPublicKey));

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(BigInt(guardianPublicKey));

      const guardianBackup = await accountContract.get_guardian_backup();
      expect(guardianBackup).to.equal(0n);
    });

    it("Expect an error when owner is zero", async function () {
      await expectRevertWithErrorMessage("argent/null-owner", async () => {
        await deployerAccount.deployContract({
          classHash: argentAccountClassHash,
          constructorCalldata: CallData.compile({ owner: 0, guardian: 12 }),
        });
      });
    });

    it("Should use signature from BOTH OWNER and GUARDIAN when there is a GUARDIAN", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      const guardianBackupBefore = await accountContract.get_guardian_backup();
      expect(guardianBackupBefore).to.equal(0n);
      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      await account.execute(accountContract.populateTransaction.change_guardian_backup(42));

      const guardianBackupAfter = await accountContract.get_guardian_backup();
      expect(guardianBackupAfter).to.equal(42n);
    });

    it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const guardianBackupPrivateKey = stark.randomAddress();
      const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey);
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      const guardianBackupBefore = await accountContract.get_guardian_backup();
      expect(guardianBackupBefore).to.equal(0n);

      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      await account.execute(accountContract.populateTransaction.change_guardian_backup(guardianBackupPublicKey));

      const guardianBackupAfter = await accountContract.get_guardian_backup();
      expect(guardianBackupAfter).to.equal(BigInt(guardianBackupPublicKey));

      account.signer = new ArgentSigner(ownerPrivateKey, guardianBackupPrivateKey);
      await account.execute(accountContract.populateTransaction.change_guardian("0x42"));

      const guardianAfter = await accountContract.get_guardian();
      expect(guardianAfter).to.equal(BigInt("0x42"));
    });

    it("Should throw an error when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const guardianBackupPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      account.signer = new ConcatSigner([ownerPrivateKey, guardianPrivateKey, guardianBackupPrivateKey]);

      await expectRevertWithErrorMessage("argent/invalid-signature-length", async () => {
        await account.execute(accountContract.populateTransaction.change_guardian("0x42"));
      });
    });

    it("Should throw an error the signature given to change owner is invalid", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account.address);
      const newOwnerPrivateKey = stark.randomAddress();
      const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);

      await expectRevertWithErrorMessage("argent/invalid-owner-sig", async () => {
        await account.execute(accountContract.populateTransaction.change_owner(newOwner, "0x12", "0x42"));
      });
    });

    it("Should be possible to change_owner", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey);
      const accountContract = await loadContract(account.address);
      const newOwnerPrivateKey = stark.randomAddress();
      const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);
      const changeOwnerSelector = hash.getSelectorFromName("change_owner");
      const chainId = await provider.getChainId();
      const contractAddress = account.address;
      const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

      const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
      const signature = ec.starkCurve.sign(msgHash, newOwnerPrivateKey);
      await account.execute(accountContract.populateTransaction.change_owner(newOwner, signature.r, signature.s));

      const owner_result = await accountContract.get_owner();
      expect(owner_result).to.equal(BigInt(newOwner));
    });
  });

  xit("Should be posssible to deploy an argent account version 0.3.0", async function () {
    // await deployAccount(argentAccountClassHash);
    // TODO Impossible atm needs not (yet) deployAccount doesn't support yet cairo1 call structure
  });
});
