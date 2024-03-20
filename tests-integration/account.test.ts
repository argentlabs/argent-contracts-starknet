import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData } from "starknet";
import {
  ArgentSigner,
  MultisigSigner,
  declareContract,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployer,
  expectRevertWithErrorMessage,
  hasOngoingEscape,
  increaseTime,
  provider,
  randomStarknetKeyPair,
  signChangeOwnerMessage,
  starknetSignatureType,
  zeroStarknetSignatureType,
  StarknetKeyPair,
} from "./lib";

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Deploy externally", async function () {
    const { accountContract, owner } = await deployAccountWithoutGuardian({ fundingAmount: 0, selfDeploy: false });

    await accountContract.get_owner_guid().should.eventually.equal(owner.guid);
    await accountContract.get_guardian().should.eventually.equal(0n);
    await accountContract.get_guardian_backup().should.eventually.equal(0n);
  });

  for (const useTxV3 of [false, true]) {
    it(`Self deployment (TxV3: ${useTxV3})`, async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian({
        useTxV3,
        selfDeploy: true,
      });

      await accountContract.get_owner_guid().should.eventually.equal(owner.guid);
      await accountContract.get_guardian().should.eventually.equal(0n);
      await accountContract.get_guardian_backup().should.eventually.equal(0n);
    });
  }

  it("Deploy two accounts with the same owner", async function () {
    const owner = randomStarknetKeyPair();
    const { accountContract: accountContract1 } = await deployAccountWithoutGuardian({ owner });
    const { accountContract: accountContract2 } = await deployAccountWithoutGuardian({ owner });
    const owner1 = await accountContract1.get_owner();
    const owner2 = await accountContract1.get_owner();
    expect(owner1).to.equal(owner2);
    expect(accountContract1.address != accountContract2.address).to.be.true;
  });

  it("Expect guardian backup to be 0 when deployed with an owner and a guardian", async function () {
    const { accountContract, owner, guardian } = await deployAccount();

    await accountContract.get_owner_guid().should.eventually.equal(owner.guid);
    await accountContract
      .get_guardian_guid()
      .should.eventually.deep.equal(new CairoOption(CairoOptionVariant.Some, guardian.guid));
    await accountContract.get_guardian_backup().should.eventually.equal(0n);
  });

  it("Expect an error when owner is zero", async function () {
    const guardian = new CairoOption(CairoOptionVariant.None);
    await expectRevertWithErrorMessage("Failed to deserialize param #1", () =>
      deployer.deployContract({
        classHash: argentAccountClassHash,
        constructorCalldata: CallData.compile({ owner: zeroStarknetSignatureType(), guardian }),
      }),
    );
  });

  it("Should use signature from BOTH OWNER and GUARDIAN when there is a GUARDIAN", async function () {
    const { account, accountContract, owner, guardian } = await deployAccount();

    await accountContract.get_guardian_backup().should.eventually.equal(0n);
    account.signer = new ArgentSigner(owner, guardian);
    const new_guardian = new StarknetKeyPair();
    await accountContract.change_guardian_backup(new_guardian.compiledSignerAsOption);

    await accountContract
      .get_guardian_backup_guid()
      .should.eventually.deep.equal(new CairoOption(CairoOptionVariant.Some, new_guardian.guid));
  });

  it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
    const guardianBackup = randomStarknetKeyPair();
    const { account, accountContract, owner, guardian } = await deployAccount();

    await accountContract.get_guardian_backup().should.eventually.equal(0n);

    account.signer = new ArgentSigner(owner, guardian);
    await accountContract.change_guardian_backup(guardianBackup.compiledSignerAsOption);

    await accountContract
      .get_guardian_backup_guid()
      .should.eventually.deep.equal(new CairoOption(CairoOptionVariant.Some, guardianBackup.guid));

    account.signer = new ArgentSigner(owner, guardianBackup);

    const new_guardian = new StarknetKeyPair();
    await accountContract.change_guardian(new_guardian.compiledSignerAsOption);

    await accountContract
      .get_guardian_guid()
      .should.eventually.deep.equal(new CairoOption(CairoOptionVariant.Some, new_guardian.guid));
  });

  it("Expect 'argent/invalid-signature-length' when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
    const { account, accountContract, owner, guardian, guardianBackup } = await deployAccountWithGuardianBackup();

    account.signer = new MultisigSigner([owner, guardian, guardianBackup]);

    const new_guardian = new StarknetKeyPair();
    await expectRevertWithErrorMessage("argent/invalid-signature-length", () =>
      accountContract.change_guardian(new_guardian.compiledSignerAsOption),
    );
  });

  it("Should be impossible to call __validate__ from outside", async function () {
    const { accountContract } = await deployAccount();
    await expectRevertWithErrorMessage("argent/non-null-caller", () => accountContract.__validate__([]));
  });

  describe("change_owner(new_owner, signature_r, signature_s)", function () {
    it("Should be possible to change_owner", async function () {
      const { accountContract, owner } = await deployAccount();
      const newOwner = randomStarknetKeyPair();

      const chainId = await provider.getChainId();
      const starknetSignature = await signChangeOwnerMessage(accountContract.address, owner.guid, newOwner, chainId);
      await accountContract.change_owner(starknetSignature);

      await accountContract.get_owner_guid().should.eventually.equal(newOwner.guid);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () =>
        accountContract.change_owner(starknetSignatureType(12, 13, 14)),
      );
    });

    it("Expect parsing error when new_owner is zero", async function () {
      const { accountContract } = await deployAccount();
      await expectRevertWithErrorMessage("Failed to deserialize param #1", () =>
        accountContract.change_owner(starknetSignatureType(0, 13, 14)),
      );
    });

    it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
      const { accountContract } = await deployAccount();
      await expectRevertWithErrorMessage("argent/invalid-owner-sig", () =>
        accountContract.change_owner(starknetSignatureType(12, 13, 14)),
      );
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();

      const newOwner = randomStarknetKeyPair();
      account.signer = new ArgentSigner(guardian);

      await accountContract.trigger_escape_owner(newOwner.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      const chainId = await provider.getChainId();
      const starknetSignature = await signChangeOwnerMessage(accountContract.address, owner.guid, newOwner, chainId);

      await accountContract.change_owner(starknetSignature);

      await accountContract.get_owner_guid().should.eventually.equal(newOwner.guid);
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  describe("change_guardian(new_guardian)", function () {
    it("Should be possible to change_guardian", async function () {
      const { accountContract } = await deployAccount();
      const newGuardian = randomStarknetKeyPair();
      await accountContract.change_guardian(newGuardian.compiledSignerAsOption);
      await accountContract
        .get_guardian()
        .should.eventually.deep.equal(new CairoOption(CairoOptionVariant.Some, newGuardian.guid));
    });

    it("Shouldn't be possible to use a guardian with pubkey = 0", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("Failed to deserialize param #1", () =>
        accountContract.change_guardian(CallData.compile([zeroStarknetSignatureType()])),
      );
    });

    it("Should be possible to change_guardian to zero when there is no backup", async function () {
      const { accountContract } = await deployAccount();
      await accountContract.change_guardian(new CairoOption(CairoOptionVariant.None));

      await accountContract.get_guardian_backup().should.eventually.equal(0n);
      await accountContract.get_guardian().should.eventually.equal(0n);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      const newGuardian = randomStarknetKeyPair();
      await expectRevertWithErrorMessage("argent/only-self", () =>
        accountContract.change_guardian(newGuardian.compiledSignerAsOption),
      );
    });

    it("Expect 'argent/backup-should-be-null' when setting the guardian to 0 if there is a backup", async function () {
      const { accountContract } = await deployAccountWithGuardianBackup();
      await accountContract.get_guardian_backup().should.eventually.not.equal(0n);
      await expectRevertWithErrorMessage("argent/backup-should-be-null", () =>
        accountContract.change_guardian(new CairoOption(CairoOptionVariant.None)),
      );
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      const newOwner = randomStarknetKeyPair();
      const newGuardian = randomStarknetKeyPair();

      await accountContract.trigger_escape_owner(newOwner.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.change_guardian(newGuardian.compiledSignerAsOption);

      await accountContract
        .get_guardian()
        .should.eventually.deep.equal(new CairoOption(CairoOptionVariant.Some, newGuardian.guid));

      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  describe("change_guardian_backup(new_guardian)", function () {
    it("Should be possible to change_guardian_backup", async function () {
      const { accountContract } = await deployAccountWithGuardianBackup();
      const newGuardianBackup = randomStarknetKeyPair();
      await accountContract.change_guardian_backup(newGuardianBackup.compiledSignerAsOption);

      await accountContract.get_guardian_backup().should.eventually.equal(newGuardianBackup.guid);
    });

    it("Should be possible to change_guardian_backup to zero", async function () {
      const { accountContract } = await deployAccountWithGuardianBackup();
      await accountContract.change_guardian_backup(new CairoOption(CairoOptionVariant.None));

      await accountContract.get_guardian_backup().should.eventually.equal(0n);
    });

    it("Expect 'argent/only-self' when called from another account", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage("argent/only-self", () =>
        accountContract.change_guardian_backup(randomStarknetKeyPair().compiledSignerAsOption),
      );
    });

    it("Expect 'argent/guardian-required' when guardian == 0 and setting a guardian backup ", async function () {
      const { accountContract } = await deployAccountWithoutGuardian();
      await accountContract.get_guardian().should.eventually.equal(0n);
      await expectRevertWithErrorMessage("argent/guardian-required", () =>
        accountContract.change_guardian_backup(randomStarknetKeyPair().compiledSignerAsOption),
      );
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccountWithGuardianBackup();

      const newOwner = randomStarknetKeyPair();
      account.signer = new ArgentSigner(guardian);
      const newGuardian = randomStarknetKeyPair();

      await accountContract.trigger_escape_owner(newOwner.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.change_guardian_backup(newGuardian.compiledSignerAsOption);

      await accountContract.get_guardian_backup().should.eventually.equal(newGuardian.guid);
      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  it("Expect 'Entry point X not found' when calling the constructor", async function () {
    const { account } = await deployAccount();
    try {
      const { transaction_hash } = await account.execute({
        contractAddress: account.address,
        entrypoint: "constructor",
        calldata: CallData.compile({ owner: 12, guardian: 13 }),
      });
      await provider.waitForTransaction(transaction_hash);
    } catch (e: any) {
      expect(e.toString()).to.contain(
        `Entry point EntryPointSelector(StarkFelt(\\"0x028ffe4ff0f226a9107253e17a904099aa4f63a02a5621de0576e5aa71bc5194\\")) not found in contract`,
      );
    }
  });
});
