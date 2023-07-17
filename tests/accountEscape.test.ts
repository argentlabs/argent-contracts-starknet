import { expect } from "chai";
import {
  ArgentSigner,
  ArgentWallet,
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
  hasOngoingEscape,
  loadContract,
  provider,
  randomKeyPair,
  setTime,
  upgradeAccount,
  declareContractFixtures
} from "./lib";

describe("ArgentAccount: escape mechanism", function () {
  let argentAccountClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;
  let randomAddress: bigint;
  let randomTime: bigint;

  const guardianType = ["guardian (no backup)", "guardian (with backup)", "backup guardian"];

  interface ArgentWalletWithOther extends ArgentWallet {
    other: KeyPair;
  }

  async function buildAccount(guardianType: string): Promise<ArgentWalletWithOther> {
    if (guardianType == "guardian (no backup)") {
      const { account, accountContract, owner, guardian } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, accountContract, owner, other: guardian };
    } else if (guardianType == "backup guardian") {
      const { account, accountContract, owner, guardianBackup } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, accountContract, owner, other: guardianBackup };
    } else if (guardianType == "guardian (with backup)") {
      const { account, accountContract, owner, guardian } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      return { account, accountContract, owner, other: guardian };
    }
    expect.fail(`Unknown type ${guardianType}`);
  }

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    oldArgentAccountClassHash = await declareContractFixtures("OldArgentAccount");
    proxyClassHash = await declareContractFixtures("Proxy");
  });

  beforeEach(async () => {
    randomAddress = randomKeyPair().publicKey;
    randomTime = BigInt(Math.floor(Math.random() * 1000));
  });

  describe("trigger_escape_owner(new_owner)", function () {
    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.trigger_escape_owner(randomAddress));
    });

    it("Expect 'argent/null-owner' when setting the new_owner to zero", async function () {
      const { account, accountContract, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = guardian;

      await expectRevertWithErrorMessage("argent/null-owner", () => accountContract.trigger_escape_owner(0));
    });

    describe("Testing with all guardian signer combination", function () {
      guardianType.forEach((type) => {
        describe(`Triggered by ${type}`, function () {
          it(`Expect to be able to trigger it alone`, async function () {
            const { account, accountContract, other } = await buildAccount(type);
            account.signer = other;

            await setTime(randomTime);
            await accountContract.trigger_escape_owner(randomAddress);
            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);
            await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.NotReady);
          });

          it(`Triggered by ${type}. Expect 'argent/cannot-override-escape' when the owner is already being escaped`, async function () {
            const { account, accountContract, owner, other } = await buildAccount(type);
            account.signer = owner;

            await accountContract.trigger_escape_guardian(randomAddress);
            const { escape_type } = await accountContract.get_escape();
            expect(escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);

            account.signer = other;
            await expectRevertWithErrorMessage("argent/cannot-override-escape", () =>
              accountContract.trigger_escape_owner(randomAddress),
            );
          });

          it("Expect to be able to trigger it alone when the previous escape expired", async function () {
            const { account, accountContract, owner, other } = await buildAccount(type);
            account.signer = other;

            await setTime(randomTime);
            account.signer = owner;
            await accountContract.trigger_escape_guardian(randomAddress);
            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);
            await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.NotReady);

            randomAddress += 1n;
            account.signer = other;
            await setTime(randomTime + ESCAPE_EXPIRY_PERIOD);
            await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Expired);
            await accountContract.trigger_escape_owner(randomAddress);
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
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.escape_owner());
    });

    it("Expect 'argent/null-owner' new_owner is zero", async function () {
      const { account, owner, guardian } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
      account.signer = guardian;

      await setTime(randomTime);
      const { transaction_hash } = await account.execute({
        contractAddress: account.address,
        entrypoint: "triggerEscapeSigner",
      });
      await provider.waitForTransaction(transaction_hash);

      account.signer = new ArgentSigner(owner, guardian);
      await upgradeAccount(account, argentAccountClassHash, ["0"]);

      const accountContract = await loadContract(account.address);
      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.cairoVersion = "1";
      account.signer = guardian;
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/null-owner", () => accountContract.escape_owner());
    });

    describe("Testing with all guardian signer combination", function () {
      guardianType.forEach((type) => {
        describe(`Escaping by ${type}`, function () {
          it("Expect to be able to escape the owner alone", async function () {
            const { account, accountContract, other } = await buildAccount(type);
            account.signer = other;

            await setTime(randomTime);
            await accountContract.trigger_escape_owner(randomAddress);
            await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
            await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Ready);

            await accountContract.escape_owner();

            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(0n);
            expect(escape.ready_at).to.equal(0n);
            expect(escape.new_signer).to.equal(0n);
            await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);

            const guardian = await accountContract.get_owner();
            expect(guardian).to.equal(randomAddress);
          });

          it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
            const { account, accountContract, other } = await buildAccount(type);
            account.signer = other;

            await setTime(randomTime);
            await accountContract.trigger_escape_owner(randomAddress);
            const { ready_at } = await accountContract.get_escape();
            expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

            await setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
            await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_owner());
          });

          it("Expect 'argent/invalid-escape' when escape status == None", async function () {
            const { account, accountContract, other } = await buildAccount(type);
            account.signer = other;

            await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_owner());
          });

          it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
            const { account, accountContract, other } = await buildAccount(type);
            account.signer = other;

            await setTime(randomTime);
            await accountContract.trigger_escape_owner(randomAddress);
            const { ready_at } = await accountContract.get_escape();
            expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

            await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
            await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_owner());
          });

          it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_OWNER", async function () {
            const { account, accountContract, owner, other } = await buildAccount(type);
            account.signer = owner;

            await setTime(randomTime);
            await accountContract.trigger_escape_guardian(randomAddress);
            const escape = await accountContract.get_escape();
            expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
            expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
            expect(escape.new_signer).to.equal(randomAddress);

            await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
            account.signer = other;
            await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_owner());
          });
        });
      });
    });
  });

  describe("trigger_escape_guardian(new_guardian)", function () {
    it("Expect the owner to be able to trigger it alone", async function () {
      const { account, accountContract, owner } = await deployAccount(argentAccountClassHash);
      account.signer = owner;

      await setTime(randomTime);
      await accountContract.trigger_escape_guardian(randomAddress);

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(randomAddress);
    });

    it("Expect the owner to be able to trigger_escape_guardian when trigger_escape_owner was performed", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = guardian;

      await setTime(randomTime);
      await accountContract.trigger_escape_owner(randomAddress);

      const escapeOwner = await accountContract.get_escape();
      expect(escapeOwner.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escapeOwner.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escapeOwner.new_signer).to.equal(randomAddress);

      // Let some block pass
      await setTime(randomTime + 10n);
      randomAddress += 1n;
      account.signer = owner;
      await accountContract.trigger_escape_guardian(randomAddress);

      const escapeGuardian = await accountContract.get_escape();
      expect(escapeGuardian.escape_type).to.equal(ESCAPE_TYPE_GUARDIAN);
      expect(escapeGuardian.ready_at).to.be.equal(randomTime + ESCAPE_SECURITY_PERIOD + 10n);
      expect(escapeGuardian.new_signer).to.equal(randomAddress);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () =>
        accountContract.trigger_escape_guardian(randomAddress),
      );
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { accountContract } = await deployAccountWithoutGuardian(argentAccountClassHash);

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      await expectRevertWithErrorMessage("argent/guardian-required", async () =>
        accountContract.trigger_escape_guardian(randomAddress),
      );
    });

    it("Expect 'argent/backup-should-be-null' escaping guardian to zero with guardian_backup being != 0", async function () {
      const { account, accountContract, owner } = await deployAccountWithGuardianBackup(argentAccountClassHash);
      account.signer = owner;

      await expectRevertWithErrorMessage("argent/backup-should-be-null", () =>
        accountContract.trigger_escape_guardian(0),
      );
    });
  });

  describe("escape_guardian()", function () {
    it("Expect the owner to be able to escape the guardian alone", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = owner;

      await setTime(randomTime);
      const oldGuardian = await accountContract.get_guardian();
      expect(oldGuardian).to.equal(guardian.publicKey);
      await accountContract.trigger_escape_guardian(randomAddress);
      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);

      await accountContract.escape_guardian();

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
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.escape_guardian());
    });

    it("Expect 'argent/guardian-required' when guardian is zero", async function () {
      const { account, accountContract, owner } = await deployAccount(argentAccountClassHash);

      await accountContract.change_guardian(0);

      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(0n);

      account.signer = owner;
      await expectRevertWithErrorMessage("argent/guardian-required", () => accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == NotReady", async function () {
      const { account, accountContract, owner } = await deployAccount(argentAccountClassHash);
      account.signer = owner;

      await setTime(randomTime);
      await accountContract.trigger_escape_guardian(randomAddress);
      const { ready_at } = await accountContract.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await setTime(randomTime + ESCAPE_SECURITY_PERIOD - 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == None", async function () {
      const { account, accountContract, owner } = await deployAccount(argentAccountClassHash);
      account.signer = owner;

      await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape status == Expired", async function () {
      const { account, accountContract, owner } = await deployAccount(argentAccountClassHash);
      account.signer = owner;

      await setTime(randomTime);
      await accountContract.trigger_escape_guardian(randomAddress);
      const { ready_at } = await accountContract.get_escape();
      expect(ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);

      await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
      await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_guardian());
    });

    it("Expect 'argent/invalid-escape' when escape_type != ESCAPE_TYPE_GUARDIAN", async function () {
      const { account, accountContract, owner, guardian } = await deployAccountWithGuardianBackup(
        argentAccountClassHash,
      );
      account.signer = guardian;

      await setTime(randomTime);
      await accountContract.trigger_escape_owner(randomAddress);
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(ESCAPE_TYPE_OWNER);
      expect(escape.ready_at).to.equal(randomTime + ESCAPE_SECURITY_PERIOD);
      expect(escape.new_signer).to.equal(randomAddress);

      await setTime(randomTime + ESCAPE_SECURITY_PERIOD);
      account.signer = owner;
      await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.escape_guardian());
    });
  });

  describe("cancel_escape()", function () {
    it("Expect the escape to be canceled when trigger_escape_owner", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = guardian;
      await accountContract.trigger_escape_owner(randomAddress);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect the escape to be canceled when trigger_escape_guardian", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = owner;
      await accountContract.trigger_escape_guardian(randomAddress);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect the escape to be canceled even if expired", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount(argentAccountClassHash);
      account.signer = owner;

      await setTime(randomTime);
      await accountContract.trigger_escape_guardian(randomAddress);
      await hasOngoingEscape(accountContract).should.eventually.be.true;

      await setTime(randomTime + ESCAPE_EXPIRY_PERIOD + 1n);
      account.signer = new ArgentSigner(owner, guardian);
      await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.Expired);

      await accountContract.cancel_escape();
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount(argentAccountClassHash);
      const { accountContract } = await deployAccount(argentAccountClassHash);
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () => accountContract.cancel_escape());
    });

    it("Expect 'argent/invalid-escape' when escape == None", async function () {
      const { accountContract } = await deployAccount(argentAccountClassHash);
      await getEscapeStatus(accountContract).should.eventually.equal(EscapeStatus.None);
      await expectRevertWithErrorMessage("argent/invalid-escape", () => accountContract.cancel_escape());
    });
  });
});
