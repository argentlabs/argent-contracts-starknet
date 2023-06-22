import { expect } from "chai";
import { Account, Contract, Signer } from "starknet";
import {
  ArgentSigner,
  ESCAPE_EXPIRY_PERIOD,
  ESCAPE_SECURITY_PERIOD,
  ESCAPE_TYPE_GUARDIAN,
  ESCAPE_TYPE_OWNER,
  EscapeStatus,
  KeyPair,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployOldAccount,
  expectRevertWithErrorMessage,
  getEscapeStatus,
  loadContract,
  provider,
  randomKeyPair,
  setTime,
  upgradeAccount,
} from "./lib";

describe("ArgentAccount: escape mechanism", function () {
  let argentAccountClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;
  let randomAddress: bigint;
  let randomTime: bigint;

  const guardianType = ["guardian (no backup)", "guardian (with backup)", "backup guardian"];

  interface ArgentWalletWithGuardian {
    account: Account;
    IAccount: Contract;
    owner: KeyPair;
    other: KeyPair;
  }

  async function buildAccount(guardianType: string): Promise<ArgentWalletWithGuardian> {
    if (guardianType == "guardian (no backup)") {
      const { account, IAccount, owner, guardian } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, IAccount, owner, other: guardian! };
    } else if (guardianType == "backup guardian") {
      const { account, IAccount, owner, guardianBackup } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, IAccount, owner, other: guardianBackup! };
    } else if (guardianType == "guardian (with backup)") {
      const { account, IAccount, owner, guardian } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, IAccount, owner, other: guardian! };
    }
    expect.fail(`Unknown type ${guardianType}`);
  }

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    oldArgentAccountClassHash = await declareContract("OldArgentAccount");
    proxyClassHash = await declareContract("Proxy");
  });

  beforeEach(async () => {
    randomAddress = BigInt(randomKeyPair().publicKey);
    randomTime = BigInt(Math.floor(Math.random() * 1000));
  });

  describe("trigger_escape_owner(new_owner)", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { IAccount } = await deployAccount(argentAccountClassHash);
      IAccount.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => IAccount.trigger_escape_owner(randomAddress));
    });

    it("Expect 'argent/null-owner' when setting the new_owner to zero", async function () {
      const { account, IAccount, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(guardian?.privateKey);

      await expectRevertWithErrorMessage("argent/null-owner", () => IAccount.trigger_escape_owner(0));
    });

    describe("Testing with all guardian signer combination", function () {
      guardianType.forEach((type) => {
        describe(`Triggered by ${type}`, function () {
          it(`Expect to be able to trigger it alone`, async function () {
            const { account, IAccount, other } = await buildAccount(type);
            account.signer = new Signer(other.privateKey);

            await setTime(randomTime);
            await IAccount.trigger_escape_owner(randomAddress);
            const escape = await IAccount.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);
            await getEscapeStatus(IAccount).should.eventually.equal(EscapeStatus.NotReady);
          });

          it(`Triggered by ${type}. Expect 'argent/cannot-override-escape' when the owner is already being escaped`, async function () {
            const { account, IAccount, owner, other } = await buildAccount(type);
            account.signer = new Signer(owner.privateKey);

            await IAccount.trigger_escape_guardian(randomAddress);
            const { escape_type } = await IAccount.get_escape();
            expect(escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);

            account.signer = new Signer(other.privateKey);
            await expectRevertWithErrorMessage("argent/cannot-override-escape", () =>
              IAccount.trigger_escape_owner(randomAddress),
            );
          });

          it("Expect to be able to trigger it alone when the previous escape expired", async function () {
            const { account, IAccount, owner, other } = await buildAccount(type);
            account.signer = new Signer(other.privateKey);

            await setTime(randomTime);
            account.signer = new Signer(owner.privateKey);
            await IAccount.trigger_escape_guardian(randomAddress);
            const escape = await IAccount.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);
            await getEscapeStatus(IAccount).should.eventually.equal(EscapeStatus.NotReady);

            randomAddress += 1n;
            account.signer = new Signer(other.privateKey);
            await setTime(randomTime + ESCAPE_EXPIRY_PERIOD);
            await getEscapeStatus(IAccount).should.eventually.equal(EscapeStatus.Expired);
            await IAccount.trigger_escape_owner(randomAddress);
            const newEscape = await IAccount.get_escape();
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
      const { IAccount } = await deployAccount(argentAccountClassHash);
      IAccount.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => IAccount.escape_owner());
    });

    it("Expect 'argent/null-owner' new_owner is zero", async function () {
      const { account, owner, guardian } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
      account.signer = new Signer(guardian?.privateKey);

      await setTime(randomTime);
      const { transaction_hash } = await account.execute({
        contractAddress: account.address,
        entrypoint: "triggerEscapeSigner",
      });
      await provider.waitForTransaction(transaction_hash);

      account.signer = new ArgentSigner(owner.privateKey, guardian?.privateKey);
      await upgradeAccount(account, argentAccountClassHash, ["0"]);

      const IAccount = await loadContract(account.address);
      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.cairoVersion = "1";
      account.signer = new Signer(guardian?.privateKey);
      IAccount.connect(account);
      await expectRevertWithErrorMessage("argent/null-owner", () => IAccount.escape_owner());
    });

    describe("Testing with all guardian signer combination", function () {
      guardianType.forEach((type) => {
        describe(`Escaping by ${type}`, function () {
          it("Expect to be able to escape the owner alone", async function () {
            const { account, IAccount, other } = await buildAccount(type);
            account.signer = new Signer(other.privateKey);

            await setTime(randomTime);
            await IAccount.trigger_escape_owner(randomAddress);
            await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
            await getEscapeStatus(IAccount).should.eventually.equal(EscapeStatus.Ready);

            await IAccount.escape_owner();

            const escape = await IAccount.get_escape();
            expect(escape.escape_type).to.equal(0n);
            expect(escape.ready_at).to.equal(0n);
            expect(escape.new_signer).to.equal(0n);
            await getEscapeStatus(IAccount).should.eventually.equal(EscapeStatus.None);

            const guardian = await IAccount.get_owner();
            expect(guardian).to.equal(randomAddress);
          });

          it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
            const { account, IAccount, other } = await buildAccount(type);
            account.signer = new Signer(other.privateKey);

            await setTime(randomTime);
            await IAccount.trigger_escape_owner(randomAddress);
            const { ready_at } = await IAccount.get_escape();
            expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

            await setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
            await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_owner());
          });

          it("Expect 'argent/invalid-escape' when escape status == None", async function () {
            const { account, IAccount, other } = await buildAccount(type);
            account.signer = new Signer(other.privateKey);

            await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_owner());
          });

          it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
            const { account, IAccount, other } = await buildAccount(type);
            account.signer = new Signer(other.privateKey);

            await setTime(randomTime);
            await IAccount.trigger_escape_owner(randomAddress);
            const { ready_at } = await IAccount.get_escape();
            expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

            await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
            await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_owner());
          });

          it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_OWNER", async function () {
            const { account, IAccount, owner, other } = await buildAccount(type);
            account.signer = new Signer(owner.privateKey);

            await setTime(randomTime);
            await IAccount.trigger_escape_guardian(randomAddress);
            const escape = await IAccount.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);

            await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
            account.signer = new Signer(other.privateKey);
            await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_owner());
          });
        });
      });
    });
  });

  describe("trigger_escape_guardian(new_guardian)", function () {
    it("Expect the owner to be able to trigger it alone", async function () {
      const { account, IAccount, owner } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(owner.privateKey);

      await setTime(randomTime);
      await IAccount.trigger_escape_guardian(randomAddress);

      const escape = await IAccount.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(randomAddress);
    });

    it("Expect the owner to be able to trigger_escape_guardian when trigger_escape_owner was performed", async function () {
      const { account, IAccount, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(guardian?.privateKey);

      await setTime(randomTime);
      await IAccount.trigger_escape_owner(randomAddress);

      const escapeOwner = await IAccount.get_escape();
      expect(escapeOwner.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escapeOwner.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escapeOwner.new_signer).to.equal(randomAddress);

      // Let some block pass
      await setTime(randomTime + 10n);
      randomAddress += 1n;
      account.signer = new Signer(owner.privateKey);
      await IAccount.trigger_escape_guardian(randomAddress);

      const escapeGuardian = await IAccount.get_escape();
      expect(escapeGuardian.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escapeGuardian.ready_at).to.be.equal(randomTime + ESCAPE_SECURITY_PERIOD + 10n);
      expect(escapeGuardian.new_signer).to.equal(randomAddress);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { IAccount } = await deployAccount(argentAccountClassHash);
      IAccount.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () =>
        IAccount.trigger_escape_guardian(randomAddress),
      );
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { IAccount } = await deployAccountWithoutGuardian(argentAccountClassHash);

      const guardian = await IAccount.get_guardian();
      expect(guardian).to.equal(0n);

      await expectRevertWithErrorMessage("argent/guardian-required", async () =>
        IAccount.trigger_escape_guardian(randomAddress),
      );
    });

    it("Expect 'argent/backup-should-be-null' escaping guardian to zero with guardian_backup being != 0", async function () {
      const { account, IAccount, owner } = await deployAccountWithGuardianBackup(argentAccountClassHash);
      account.signer = new Signer(owner.privateKey);

      await expectRevertWithErrorMessage("argent/backup-should-be-null", () =>
        IAccount.trigger_escape_guardian(0),
      );
    });
  });

  describe("escape_guardian()", function () {
    it("Expect the owner to be able to escape the guardian alone", async function () {
      const { account, IAccount, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(owner.privateKey);

      await setTime(randomTime);
      const oldGuardian = await IAccount.get_guardian();
      expect(oldGuardian).to.equal(BigInt(guardian?.publicKey ?? 0));
      await IAccount.trigger_escape_guardian(randomAddress);
      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);

      await IAccount.escape_guardian();

      const escape = await IAccount.get_escape();
      expect(escape.escape_type).to.equal(0n);
      expect(escape.ready_at).to.equal(0n);
      expect(escape.new_signer).to.equal(0n);
      const newGuardian = await IAccount.get_guardian();
      expect(newGuardian).to.equal(randomAddress);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { IAccount } = await deployAccount(argentAccountClassHash);
      IAccount.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => IAccount.escape_guardian());
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { account, IAccount, owner } = await deployAccount(argentAccountClassHash);

      await IAccount.change_guardian(0);

      const guardian = await IAccount.get_guardian();
      expect(guardian).to.equal(0n);

      account.signer = new Signer(owner.privateKey);
      await expectRevertWithErrorMessage("argent/guardian-required", () => IAccount.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
      const { account, IAccount, owner } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(owner.privateKey);

      await setTime(randomTime);
      await IAccount.trigger_escape_guardian(randomAddress);
      const { ready_at } = await IAccount.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == None", async function () {
      const { account, IAccount, owner } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(owner.privateKey);

      await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
      const { account, IAccount, owner } = await deployAccount(argentAccountClassHash);
      account.signer = new Signer(owner.privateKey);

      await setTime(randomTime);
      await IAccount.trigger_escape_guardian(randomAddress);
      const { ready_at } = await IAccount.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_GUARDIAN", async function () {
      const { account, IAccount, owner, guardian } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      account.signer = new Signer(guardian?.privateKey);

      await setTime(randomTime);
      await IAccount.trigger_escape_owner(randomAddress);
      const escape = await IAccount.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(randomAddress);

      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.signer = new Signer(owner.privateKey);
      await expectRevertWithErrorMessage("argent/invalid-escape", () => IAccount.escape_guardian());
    });
  });
});
