import { expect } from "chai";
import { Signer } from "starknet";
import {
  declareContract,
  deployAccountV2,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  expectRevertWithErrorMessage,
  increaseTime,
  setTime,
} from "./shared";

describe("ArgentAccount: escape mechanism", function () {
  // Avoid timeout
  this.timeout(320000);

  const ESCAPE_TYPE_GUARDIAN = 1n;
  const ESCAPE_TYPE_OWNER = 2n;
  const ESCAPE_SECURITY_PERIOD = 7n * 24n * 60n * 60n; // 7 days
  const ESCAPE_EXPIRY_PERIOD = 2n * 7n * 24n * 60n * 60n; // 14 days
  // TODO Update tests if get_escape returns EscapeStatus
  // enum EscapeStatus {
  //   None,
  //   NotReady,
  //   Ready,
  //   Expired
  // }
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  describe("trigger_escape_owner(new_owner)", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccountV2(argentAccountClassHash);
      const { accountContract } = await deployAccountV2(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
      });
    });

    it("Expect 'argent/null-owner' when setting the new_owner to zero", async function () {
      const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
      account.signer = new Signer(guardianPrivateKey);

      await expectRevertWithErrorMessage("argent/null-owner", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(0));
      });
    });

    describe("Triggered with the guardian as a signer", function () {
      it("Expect the guardian to be able to trigger it alone", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);
      });

      it("Expect 'argent/cannot-override-escape' when the guardian is already being escaped", async function () {
        const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccountV2(
          argentAccountClassHash,
        );
        account.signer = new Signer(ownerPrivateKey);

        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);

        account.signer = new Signer(guardianPrivateKey);
        await expectRevertWithErrorMessage("argent/cannot-override-escape", async () => {
          await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        });
      });

      it("Expect the guardian to be able to trigger it alone when the previous escape is expired", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await increaseTime(ESCAPE_EXPIRY_PERIOD);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const newEscape = await accountContract.get_escape();
        expect(newEscape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
        expect(newEscape.active_at >= 42n + ESCAPE_SECURITY_PERIOD + ESCAPE_EXPIRY_PERIOD).to.be.true;
      });
    });

    describe("Triggered with the guardian backup as a signer", function () {
      it("Expect the backup guardian to be able to trigger it alone", async function () {
        const { account, accountContract, guardianBackupPrivateKey } = await deployAccountWithGuardianBackup(
          argentAccountClassHash,
        );
        account.signer = new Signer(guardianBackupPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);
      });

      it("Expect 'argent/cannot-override-escape' when the guardian is already being escaped calling from the guardian backup", async function () {
        const { account, accountContract, ownerPrivateKey, guardianBackupPrivateKey } =
          await deployAccountWithGuardianBackup(argentAccountClassHash);
        account.signer = new Signer(ownerPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);

        account.signer = new Signer(guardianBackupPrivateKey);
        await expectRevertWithErrorMessage("argent/cannot-override-escape", async () => {
          await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        });
      });

      it("Expect the guardian to be able to trigger it alone when the previous escape is expired", async function () {
        const { account, accountContract, guardianBackupPrivateKey } = await deployAccountWithGuardianBackup(
          argentAccountClassHash,
        );
        account.signer = new Signer(guardianBackupPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await increaseTime(ESCAPE_EXPIRY_PERIOD);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const newEscape = await accountContract.get_escape();
        expect(newEscape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
        expect(newEscape.active_at >= 42n + ESCAPE_SECURITY_PERIOD + ESCAPE_EXPIRY_PERIOD).to.be.true;
      });
    });
  });

  describe("escape_owner()", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccountV2(argentAccountClassHash);
      const { accountContract } = await deployAccountV2(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", async () => {
        await account.execute(accountContract.populateTransaction.escape_owner());
      });
    });

    describe("Escaping with the guardian as a signer", function () {
      it("Expect the guardian to be able to escape the owner alone", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        await increaseTime(ESCAPE_SECURITY_PERIOD);

        await account.execute(accountContract.populateTransaction.escape_owner());

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(0n);
        expect(escape.active_at).to.equal(0n);
        const guardian = await accountContract.get_owner();
        expect(guardian).to.equal(42n);
      });

      it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_SECURITY_PERIOD - 1n);
        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });

      it("Expect 'argent/invalid-escape' when escape status == None", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });

      it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_EXPIRY_PERIOD + 1n);
        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });

      it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_OWNER", async function () {
        const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccountV2(
          argentAccountClassHash,
        );
        account.signer = new Signer(ownerPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_SECURITY_PERIOD);
        account.signer = new Signer(guardianPrivateKey);
        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });
    });

    describe("Escaping with the guardian backup as a signer", function () {
      it("Expect the guardian to be able to escape the owner alone", async function () {
        const { account, accountContract, guardianBackupPrivateKey } = await deployAccountWithGuardianBackup(
          argentAccountClassHash,
        );
        account.signer = new Signer(guardianBackupPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        await increaseTime(ESCAPE_SECURITY_PERIOD);

        await account.execute(accountContract.populateTransaction.escape_owner());

        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(0n);
        expect(escape.active_at).to.equal(0n);
        const guardian = await accountContract.get_owner();
        expect(guardian).to.equal(42n);
      });

      it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
        const { account, accountContract, guardianBackupPrivateKey } = await deployAccountWithGuardianBackup(
          argentAccountClassHash,
        );
        account.signer = new Signer(guardianBackupPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_SECURITY_PERIOD - 1n);
        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });

      it("Expect 'argent/invalid-escape' when escape status == None", async function () {
        const { account, accountContract, guardianBackupPrivateKey } = await deployAccountWithGuardianBackup(
          argentAccountClassHash,
        );
        account.signer = new Signer(guardianBackupPrivateKey);

        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });
      it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
        const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
        account.signer = new Signer(guardianPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_owner(42));
        const escape = await accountContract.get_escape();
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_EXPIRY_PERIOD + 1n);
        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });

      it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_OWNER", async function () {
        const { account, accountContract, ownerPrivateKey, guardianBackupPrivateKey } =
          await deployAccountWithGuardianBackup(argentAccountClassHash);
        account.signer = new Signer(ownerPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_SECURITY_PERIOD);
        account.signer = new Signer(guardianBackupPrivateKey);
        await expectRevertWithErrorMessage("argent/invalid-escape", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });

      // TODO Ongoing (need upgrade)
      it("Expect 'argent/null-owner' new_owner is zero", async function () {
        const { account, accountContract, ownerPrivateKey, guardianBackupPrivateKey } =
          await deployAccountWithGuardianBackup(argentAccountClassHash);
        account.signer = new Signer(ownerPrivateKey);

        await setTime(42);
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
        const escape = await accountContract.get_escape();
        expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
        expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);

        await setTime(42n + ESCAPE_SECURITY_PERIOD);
        account.signer = new Signer(guardianBackupPrivateKey);
        await expectRevertWithErrorMessage("argent/null-owner", async () => {
          await account.execute(accountContract.populateTransaction.escape_owner());
        });
      });
    });
  });

  describe("trigger_escape_guardian(new_guardian)", function () {
    it("Expect the owner to be able to trigger it alone", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccountV2(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);
      await setTime(42);

      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(43));

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escape.active_at).to.equal(42n + ESCAPE_SECURITY_PERIOD);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccountV2(argentAccountClassHash);
      const { accountContract } = await deployAccountV2(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
      });
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { account, accountContract } = await deployAccountWithoutGuardian(argentAccountClassHash);

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      await expectRevertWithErrorMessage("argent/guardian-required", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(42));
      });
    });

    it("Expect 'argent/backup-should-be-null' escaping guardian to zero with guardian_backup being != 0", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      account.signer = new Signer(ownerPrivateKey);

      await expectRevertWithErrorMessage("argent/backup-should-be-null", async () => {
        await account.execute(accountContract.populateTransaction.trigger_escape_guardian(0));
      });
    });
  });

  describe("escape_guardian()", function () {
    it("Expect the owner to be able to escape the guardian alone", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccountV2(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);

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
