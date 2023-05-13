import { expect } from "chai";
import { Signer, ec, stark } from "starknet";
import {
  ConcatSigner,
  declareContract,
  deployAccount,
  expectRevertWithErrorMessage,
  increaseTime,
  loadContract,
  setTime,
} from "./shared";

describe("ArgentAccount: escape mechanism", function () {
  // Avoid timeout
  this.timeout(320000);

  const GUARDIAN_ESCAPE_TYPE = 1n;
  const OWNER_ESCAPE_TYPE = 2n;
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  describe("trigger_escape_owner(new_owner)", function () {
    it("Expect the guardian to be able to trigger it alone", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      account.signer = new Signer(guardianPrivateKey);
      await setTime(42);
      accountContract.connect(account);

      await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(OWNER_ESCAPE_TYPE);
      expect(escape.active_at).to.equal(42n + 604800n);
    });

    it("Expect the backup guardian to be able to trigger it alone", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const guardianBackupPrivateKey = stark.randomAddress();
      const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey)
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      account.signer = new ConcatSigner([ownerPrivateKey, guardianPrivateKey]);
      await account.execute(accountContract.populateTransaction.change_guardian_backup(guardianBackupPublicKey));
      await setTime(42);
      accountContract.connect(account);

      account.signer = new Signer(guardianBackupPrivateKey);
      await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(OWNER_ESCAPE_TYPE);
      expect(escape.active_at).to.equal(42n + 604800n);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const account1 = await deployAccount(argentAccountClassHash);
      const account2 = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account2.address);

      await expectRevertWithErrorMessage("argent/only-self", async () => {
        await account1.execute(accountContract.populateTransaction.trigger_escape_owner(42));
      });
    });

    // TODO Is this test relevant?
    // it("Expect an error when guardian is zero", async function () {
    //   const account = await deployAccount(argentAccountClassHash);
    //   const accountContract = await loadContract(account.address);

    //   const guardian = await accountContract.get_guardian();
    //   expect(guardian).to.equal(0n);

    //   await expectRevertWithErrorMessage("argent/guardian-required", async () => {
    //     await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
    //   });
    // });

    it("Expect 'argent/null-owner' when setting the new_owner to zero", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      account.signer = new Signer(guardianPrivateKey);
      await expectRevertWithErrorMessage("argent/null-owner", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(0));
      });
    });

    // TODO Do with guardian backup
    it("Expect 'argent/cannot-override-escape' when the guardian is being escaped", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(GUARDIAN_ESCAPE_TYPE);
      
      account.signer = new Signer(guardianPrivateKey);
      await expectRevertWithErrorMessage("argent/cannot-override-escape", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
      });
    });
  });

  describe("escape_owner()", function () {
    it("Expect the guardian to be able to escape the owner alone", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);
      account.signer = new Signer(guardianPrivateKey);

      await setTime(42);
      await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
      await increaseTime(604800);

      await account.execute(accountContract.populateTransaction.escape_owner());

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(0n);
      expect(escape.active_at).to.equal(0n);
      const guardian = await accountContract.get_owner();
      expect(guardian).to.equal(42n);
    });
  });

  describe("trigger_escape_guardian(new_guardian)", function () {
    it("Expect the owner to be able to trigger it alone", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      await setTime(42);
      accountContract.connect(account);

      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(43));

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(GUARDIAN_ESCAPE_TYPE);
      expect(escape.active_at).to.equal(42n + 604800n);
    });
  });

  describe("escape_guardian()", function () {
    it("Expect the owner to be able to escape the guardian alone", async function () {
      const privateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, privateKey, "0x42");
      const accountContract = await loadContract(account.address);

      await setTime(42);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(43));
      await increaseTime(604800);

      await account.execute(accountContract.populateTransaction.escape_guardian());

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(0n);
      expect(escape.active_at).to.equal(0n);
      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(43n);
    });
  });
});
