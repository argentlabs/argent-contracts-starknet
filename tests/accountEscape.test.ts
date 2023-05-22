import { expect } from "chai";
import { Account, Contract, Signer, ec, num } from "starknet";
import {
  ArgentSigner,
  ESCAPE_EXPIRY_PERIOD,
  ESCAPE_SECURITY_PERIOD,
  EscapeStatus,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployOldAccount,
  expectRevertWithErrorMessage,
  getEscapeStatus,
  loadContract,
  provider,
  randomPrivateKey,
  setTime,
  upgradeAccount,
} from "./lib";

describe.only("ArgentAccount: escape mechanism", function () {
  const ESCAPE_TYPE_GUARDIAN = 1n;
  const ESCAPE_TYPE_OWNER = 2n;

  let argentAccountClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;
  let randomAddress: bigint;
  let randomTime: bigint;

  const guardianType = ["guardian (no backup)", "guardian (with backup)", "backup guardian"];

  interface GuardianAccount {
    account: Account;
    accountContract: Contract;
    ownerPrivateKey: string;
    otherPrivateKey: string;
  }

  async function buildAccount(guardianType: string): Promise<GuardianAccount> {
    if (guardianType == "guardian (no backup)") {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, accountContract, ownerPrivateKey, otherPrivateKey: guardianPrivateKey as string };
    } else if (guardianType == "backup guardian") {
      const { account, accountContract, ownerPrivateKey, guardianBackupPrivateKey } =
        await deployAccountWithGuardianBackup(argentAccountClassHash);
      return { account, accountContract, ownerPrivateKey, otherPrivateKey: guardianBackupPrivateKey as string };
    } else if (guardianType == "guardian (with backup)") {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, accountContract, ownerPrivateKey, otherPrivateKey: guardianPrivateKey as string };
    }
    expect.fail(`Unknown type ${guardianType}`);
  }

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    oldArgentAccountClassHash = await declareContract("OldArgentAccount");
    proxyClassHash = await declareContract("Proxy");
  });

  beforeEach(async () => {
    randomAddress = num.toBigInt(ec.starkCurve.getStarkKey(randomPrivateKey()));
    randomTime = BigInt(Math.floor(Math.random() * 1000));
  });

  describe("trigger_escape_owner(new_owner)", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", () =>
        account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress)),
      );
    });

    it("Expect 'argent/null-owner' when setting the new_owner to zero", async function () {
      const { account, accountContract, guardianPrivateKey } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(guardianPrivateKey);

      await expectRevertWithErrorMessage("argent/null-owner", () =>
        account.execute(accountContract.populateTransaction.trigger_escape_owner(0)),
      );
    });

    describe("Testing with all guardian signer combination", function () {
      guardianType.forEach((type) => {
        describe(`Triggered by ${type}`, function () {
          it(`Expect to be able to trigger it alone`, async function () {
            const { account, accountContract, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(otherPrivateKey);

            await setTime(randomTime);
            await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));
            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);
            expect(await getEscapeStatus(accountContract)).to.equal(EscapeStatus.NotReady);
          });

          it(`Triggered by ${type}. Expect 'argent/cannot-override-escape' when the owner is already being escaped`, async function () {
            const { account, accountContract, ownerPrivateKey, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(ownerPrivateKey);

            await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));
            const { escape_type } = await accountContract.get_escape();
            expect(escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);

            account.signer = new Signer(otherPrivateKey);
            await expectRevertWithErrorMessage("argent/cannot-override-escape", () =>
              account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress)),
            );
          });

          it("Expect to be able to trigger it alone when the previous escape expired", async function () {
            const { account, accountContract, ownerPrivateKey, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(otherPrivateKey);

            await setTime(randomTime);
            account.signer = new Signer(ownerPrivateKey);
            await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));
            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);
            expect(await getEscapeStatus(accountContract)).to.equal(EscapeStatus.NotReady);

            randomAddress += 1n;
            account.signer = new Signer(otherPrivateKey);
            await setTime(randomTime + ESCAPE_EXPIRY_PERIOD);
            expect(await getEscapeStatus(accountContract)).to.equal(EscapeStatus.Expired);
            await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));
            const newEscape = await accountContract.get_escape();
            expect(newEscape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
            expect(newEscape.ready_at >= randomTime + ESCAPE_SECURITY_PERIOD + ESCAPE_EXPIRY_PERIOD).to.be.true;
            expect(newEscape.new_signer).to.equal(randomAddress);
          });
        });
      });
    });
  });

  describe("escape_owner()", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", () =>
        account.execute(accountContract.populateTransaction.escape_owner()),
      );
    });

    it("Expect 'argent/null-owner' new_owner is zero", async function () {
      const { account, ownerPrivateKey, guardianPrivateKey } = await deployOldAccount(
        proxyClassHash,
        oldArgentAccountClassHash,
      );
      account.signer = new Signer(guardianPrivateKey);

      await setTime(randomTime);
      const { transaction_hash } = await account.execute({
        contractAddress: account.address,
        entrypoint: "triggerEscapeSigner",
      });
      await provider.waitForTransaction(transaction_hash);

      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      await upgradeAccount(account, argentAccountClassHash, ["0"]);

      const accountContract = await loadContract(account.address);
      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.cairoVersion = "1";
      account.signer = new Signer(guardianPrivateKey);
      await expectRevertWithErrorMessage("argent/null-owner", () =>
        account.execute(accountContract.populateTransaction.escape_owner()),
      );
    });

    describe("Testing with all guardian signer combination", function () {
      guardianType.forEach((type) => {
        describe(`Escaping by ${type}`, function () {
          it("Expect to be able to escape the owner alone", async function () {
            const { account, accountContract, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(otherPrivateKey);

            await setTime(randomTime);
            await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));
            await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(await getEscapeStatus(accountContract)).to.equal(EscapeStatus.Ready);

            await account.execute(accountContract.populateTransaction.escape_owner());

            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(0n);
            expect(escape.ready_at).to.equal(0n);
            expect(escape.new_signer).to.equal(0n);
            expect(await getEscapeStatus(accountContract)).to.equal(EscapeStatus.None);

            const guardian = await accountContract.get_owner();
            expect(guardian).to.equal(randomAddress);
          });

          it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
            const { account, accountContract, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(otherPrivateKey);

            await setTime(randomTime);
            await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));
            const { ready_at } = await accountContract.get_escape();
            expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

            await setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
            await expectRevertWithErrorMessage("argent/invalid-escape", () =>
              account.execute(accountContract.populateTransaction.escape_owner()),
            );
          });

          it("Expect 'argent/invalid-escape' when escape status == None", async function () {
            const { account, accountContract, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(otherPrivateKey);

            await expectRevertWithErrorMessage("argent/invalid-escape", () =>
              account.execute(accountContract.populateTransaction.escape_owner()),
            );
          });

          it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
            const { account, accountContract, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(otherPrivateKey);

            await setTime(randomTime);
            await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));
            const { ready_at } = await accountContract.get_escape();
            expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

            await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
            await expectRevertWithErrorMessage("argent/invalid-escape", () =>
              account.execute(accountContract.populateTransaction.escape_owner()),
            );
          });

          it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_OWNER", async function () {
            const { account, accountContract, ownerPrivateKey, otherPrivateKey } = await buildAccount(type);
            account.signer = new Signer(ownerPrivateKey);

            await setTime(randomTime);
            await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));
            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);

            await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
            account.signer = new Signer(otherPrivateKey);
            await expectRevertWithErrorMessage("argent/invalid-escape", () =>
              account.execute(accountContract.populateTransaction.escape_owner()),
            );
          });
        });
      });
    });
  });

  describe("trigger_escape_guardian(new_guardian)", function () {
    it("Expect the owner to be able to trigger it alone", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);

      await setTime(randomTime);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(randomAddress);
    });

    it("Expect the owner to be able to trigger_escape_guardian when trigger_escape_owner was performed", async function () {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccount(
        argentAccountClassHash,
      );
      account.signer = new Signer(guardianPrivateKey);

      await setTime(randomTime);
      await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));

      const escapeOwner = await accountContract.get_escape();
      expect(escapeOwner.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escapeOwner.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escapeOwner.new_signer).to.equal(randomAddress);

      // Let some block pass
      await setTime(randomTime + 10n);
      randomAddress += 1n;
      account.signer = new Signer(ownerPrivateKey);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));

      const escapeGuardian = await accountContract.get_escape();
      expect(escapeGuardian.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escapeGuardian.ready_at).to.be.equal(randomTime + ESCAPE_SECURITY_PERIOD + 10n);
      expect(escapeGuardian.new_signer).to.equal(randomAddress);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", () =>
        account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress)),
      );
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { account, accountContract } = await deployAccountWithoutGuardian(argentAccountClassHash);

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      await expectRevertWithErrorMessage("argent/guardian-required", async () =>
        account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress)),
      );
    });

    it("Expect 'argent/backup-should-be-null' escaping guardian to zero with guardian_backup being != 0", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      account.signer = new Signer(ownerPrivateKey);

      await expectRevertWithErrorMessage("argent/backup-should-be-null", () =>
        account.execute(accountContract.populateTransaction.trigger_escape_guardian(0)),
      );
    });
  });

  describe("escape_guardian()", function () {
    it("Expect the owner to be able to escape the guardian alone", async function () {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccount(
        argentAccountClassHash,
      );
      account.signer = new Signer(ownerPrivateKey);
      const guardianPublicKey = BigInt(ec.starkCurve.getStarkKey(guardianPrivateKey as string));

      await setTime(randomTime);
      const oldGuardian = await accountContract.get_guardian();
      expect(oldGuardian).to.equal(guardianPublicKey);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));
      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);

      await account.execute(accountContract.populateTransaction.escape_guardian());

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(0n);
      expect(escape.ready_at).to.equal(0n);
      expect(escape.new_signer).to.equal(0n);
      const newGuardian = await accountContract.get_guardian();
      expect(newGuardian).to.equal(randomAddress);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/only-self", () =>
        account.execute(accountContract.populateTransaction.escape_guardian()),
      );
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);

      await account.execute(accountContract.populateTransaction.change_guardian(0));

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      account.signer = new Signer(ownerPrivateKey);
      await expectRevertWithErrorMessage("argent/guardian-required", () =>
        account.execute(accountContract.populateTransaction.escape_guardian()),
      );
    });

    it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);

      await setTime(randomTime);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));
      const { ready_at } = await accountContract.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", () =>
        account.execute(accountContract.populateTransaction.escape_guardian()),
      );
    });

    it("Expect 'argent/invalid-escape' when escape status == None", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);

      await expectRevertWithErrorMessage("argent/invalid-escape", () =>
        account.execute(accountContract.populateTransaction.escape_guardian()),
      );
    });

    it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);

      await setTime(randomTime);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian(randomAddress));
      const { ready_at } = await accountContract.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", () =>
        account.execute(accountContract.populateTransaction.escape_guardian()),
      );
    });

    it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_GUARDIAN", async function () {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      account.signer = new Signer(guardianPrivateKey);

      await setTime(randomTime);
      await account.execute(accountContract.populateTransaction.trigger_escape_owner(randomAddress));
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(randomAddress);

      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.signer = new Signer(ownerPrivateKey);
      await expectRevertWithErrorMessage("argent/invalid-escape", () =>
        account.execute(accountContract.populateTransaction.escape_guardian()),
      );
    });
  });
});
