import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData, Contract, hash, RawArgs } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  ContractWithClass,
  deployAccount,
  deployAccountWithoutGuardians,
  deployLegacyAccount,
  deployLegacyAccountWithoutGuardian,
  deployOldAccountWithProxy,
  deployOldAccountWithProxyWithoutGuardian,
  expectEvent,
  expectRevertWithErrorMessage,
  getUpgradeDataLegacy,
  LegacyWebauthnOwner,
  manager,
  randomEip191KeyPair,
  randomEthKeyPair,
  randomSecp256r1KeyPair,
  randomStarknetKeyPair,
  randomWebauthnLegacyOwner,
  RawSigner,
  StarknetKeyPair,
  upgradeAccount,
  WebauthnOwner,
} from "../../lib";

interface SelfCall {
  entrypoint: string;
  calldata?: RawArgs;
}

interface DeployAccountReturn {
  account: ArgentAccount;
  accountContract: Contract;
  owner: RawSigner;
  guardian?: RawSigner;
}
interface UpgradeDataEntry {
  name: string;
  deployAccount: () => Promise<DeployAccountReturn>;
  deployAccountWithoutGuardians: () => Promise<DeployAccountReturn>;
  upgradeExtraCalldata?: string[]; // Optional, as it's not present in all entries
  triggerEscapeOwnerCall: SelfCall;
  triggerEscapeGuardianCall: SelfCall;
}

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;
  let classHashV040: string;
  const upgradeData: UpgradeDataEntry[] = [];

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.deployContract("MockDapp");

    upgradeData.push({
      name: "0.2.3.1",
      deployAccount: async () => await deployOldAccountWithProxy(),
      // Required to ensure execute_after_upgrade is called. Without any calldata, the execute_after_upgrade won't be called
      upgradeExtraCalldata: ["0"],
      deployAccountWithoutGuardians: async () => await deployOldAccountWithProxyWithoutGuardian(),
      // Gotta call like that as the entrypoint is not found on the contract for legacy versions
      triggerEscapeOwnerCall: { entrypoint: "triggerEscapeSigner" },
      triggerEscapeGuardianCall: { entrypoint: "triggerEscapeGuardian" },
    });

    const v030 = "0.3.0";
    const classHashV030 = await manager.declareArtifactAccountContract(v030);
    const triggerEscapeOwnerCallV03 = { entrypoint: "trigger_escape_owner", calldata: [12] };
    const triggerEscapeGuardianCallV03 = { entrypoint: "trigger_escape_guardian", calldata: [12] };
    upgradeData.push({
      name: v030,
      deployAccount: async () => deployLegacyAccount(classHashV030),
      deployAccountWithoutGuardians: async () => deployLegacyAccountWithoutGuardian(classHashV030),
      triggerEscapeOwnerCall: triggerEscapeOwnerCallV03,
      triggerEscapeGuardianCall: triggerEscapeGuardianCallV03,
    });

    const v031 = "0.3.1";
    const classHashV031 = await manager.declareArtifactAccountContract(v031);
    upgradeData.push({
      name: v031,
      deployAccount: async () => deployLegacyAccount(classHashV031),
      deployAccountWithoutGuardians: async () => deployLegacyAccountWithoutGuardian(classHashV031),
      triggerEscapeOwnerCall: triggerEscapeOwnerCallV03,
      triggerEscapeGuardianCall: triggerEscapeGuardianCallV03,
    });

    const v040 = "0.4.0";
    classHashV040 = await manager.declareArtifactAccountContract(v040);
    const triggerEscapeOwnerCallV04 = {
      entrypoint: "trigger_escape_owner",
      calldata: CallData.compile(randomStarknetKeyPair().compiledSigner),
    };
    const triggerEscapeGuardianCallV04 = {
      entrypoint: "trigger_escape_guardian",
      calldata: CallData.compile([new CairoOption(CairoOptionVariant.None)]),
    };
    upgradeData.push({
      name: v040,
      deployAccount: async () => deployAccount({ classHash: classHashV040 }),
      deployAccountWithoutGuardians: async () => deployAccountWithoutGuardians({ classHash: classHashV040 }),
      triggerEscapeOwnerCall: triggerEscapeOwnerCallV04,
      triggerEscapeGuardianCall: triggerEscapeGuardianCallV04,
    });
  });

  it("Waiting for upgradeData to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const {
        name,
        deployAccount,
        triggerEscapeOwnerCall,
        triggerEscapeGuardianCall,
        deployAccountWithoutGuardians,
        upgradeExtraCalldata,
      } of upgradeData) {
        it(`[${name}] Should be possible to upgrade `, async function () {
          const { account } = await deployAccount();
          const txReceipt = await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          // Check events
          const eventsEmittedByAccount = txReceipt.events.filter((e) => e.from_address === account.address);

          const expectedEvents = ["OwnerAddedGuid", "GuardianAddedGuid"];

          const [major, minor] = name.split(".").map(Number);
          if (major > 0 || minor >= 3) {
            // >= 0.3.*
            expectedEvents.push("TransactionExecuted", "AccountUpgraded");
          } else {
            expectedEvents.push("transaction_executed", "account_upgraded");
          }
          if (major === 0 && minor < 4) {
            // < 0.4.*
            expectedEvents.push("SignerLinked", "SignerLinked");
          }

          const missingEvents = [];
          for (const expectedEventName of expectedEvents) {
            const eventIndex = eventsEmittedByAccount.findIndex(
              (event) => event.keys?.[0] === hash.getSelectorFromName(expectedEventName),
            );
            if (eventIndex === -1) {
              missingEvents.push(expectedEventName);
            } else {
              eventsEmittedByAccount.splice(eventIndex, 1);
            }
          }
          expect(missingEvents).to.have.lengthOf(0, `Expected events ${missingEvents.join(", ")} not found`);
          expect(eventsEmittedByAccount).to.have.lengthOf(
            0,
            `Unexpected events ${eventsEmittedByAccount.join(", ")} found`,
          );

          mockDapp.connect(account);
          // This should work as long as we support the "old" signature format [r1, s1, r2, s2]
          account.cairoVersion = "1";
          await manager.ensureSuccess(mockDapp.set_number(42));
        });

        it(`[${name}] Should be possible to upgrade without guardian from ${name}`, async function () {
          const { account } = await deployAccountWithoutGuardians();
          await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          account.cairoVersion = "1";
          await manager.ensureSuccess(mockDapp.set_number(42));
        });

        it(`[${name}] Upgrade cairo with multicall`, async function () {
          const random = randomStarknetKeyPair().publicKey;
          const { account } = await deployAccount();
          const upgradeData = account.cairoVersion
            ? CallData.compile([[mockDapp.populateTransaction.set_number(random)]])
            : getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(random)]);
          await upgradeAccount(account, argentAccountClassHash, upgradeData);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          await mockDapp.get_number(account.address).should.eventually.equal(random);
          // We don't really care about the value here, just that it is successful
          await manager.ensureSuccess(mockDapp.set_number(random));
        });

        it(`[${name}] Should be possible to upgrade if an owner escape is ongoing`, async function () {
          const { account, guardian } = await deployAccount();

          const oldSigner = account.signer;

          if (guardian instanceof StarknetKeyPair) {
            account.signer = new ArgentSigner(guardian);
          } else if (guardian) {
            account.signer = guardian;
          }

          await manager.ensureSuccess(
            account.execute({
              contractAddress: account.address,
              ...triggerEscapeOwnerCall,
            }),
          );

          account.signer = oldSigner;
          await expectEvent(await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata), {
            from_address: account.address,
            eventName: "EscapeCanceled",
          });
        });

        it(`[${name}] Should be possible to upgrade if a guardian escape is ongoing`, async function () {
          const { account, owner } = await deployAccount();

          const oldSigner = account.signer;

          if (owner instanceof StarknetKeyPair) {
            account.signer = new ArgentSigner(owner);
          } else {
            account.signer = owner;
          }

          await manager.ensureSuccess(
            account.execute({
              contractAddress: account.address,
              ...triggerEscapeGuardianCall,
            }),
          );

          account.signer = oldSigner;
          await expectEvent(await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata), {
            from_address: account.address,
            eventName: "EscapeCanceled",
          });
        });
      }
    });
  });

  it("Upgrade from current version FutureVersion", async function () {
    const argentAccountFutureClassHash = await manager.declareLocalContract("MockFutureArgentAccount");
    const { account } = await deployAccount();

    const response = await upgradeAccount(account, argentAccountFutureClassHash);
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountFutureClassHash));

    const data = [argentAccountFutureClassHash];
    await expectEvent(response, { from_address: account.address, eventName: "AccountUpgraded", data });
  });

  it.skip("Reject invalid upgrade targets", async function () {
    const { account } = await deployAccount();

    await upgradeAccount(account, "0x1").should.be.rejectedWith(
      "Class with hash 0x0000000000000000000000000000000000000000000000000000000000000001 is not declared.",
    );

    await upgradeAccount(account, mockDapp.classHash).should.be.rejectedWith(
      "Entry point EntryPointSelector(0xfe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283) not found in contract.",
    );
  });

  it("Shouldn't upgrade from current version to itself", async function () {
    const { account } = await deployAccount();
    await expectRevertWithErrorMessage("argent/downgrade-not-allowed", upgradeAccount(account, argentAccountClassHash));
  });

  describe("Testing recovery_from_legacy_upgrade when upgrading from 0.2.3", function () {
    it("Should be possible to recover the signer", async function () {
      const { account, owner } = await deployOldAccountWithProxy();
      const legacyClassHash = await manager.getClassHashAt(account.address);
      await upgradeAccount(account, argentAccountClassHash, []);

      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(legacyClassHash));
      account.cairoVersion = "1";
      mockDapp.connect(account);

      // Check the account is in the wrong state
      const wrongGuids = await account.callContract({
        contractAddress: account.address,
        entrypoint: "get_owners_guids",
      });
      // Since we have to do a raw call, we have the unparsed value returned
      expect(wrongGuids.length).to.equal(1);
      expect(wrongGuids[0]).to.equal("0x0");
      await expectRevertWithErrorMessage("argent/no-single-stark-owner", mockDapp.set_number(56));

      const { account: otherAccount } = await deployAccount();
      // Recover the signer
      await otherAccount.execute({
        contractAddress: account.address,
        entrypoint: "recovery_from_legacy_upgrade",
        calldata: [],
      });
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      // Making sure it has the new owner migrated correctly
      const newAccountContract = await manager.loadContract(account.address);
      const newGuid = new StarknetKeyPair(owner.privateKey).guid;
      expect(await newAccountContract.get_owners_guids()).to.deep.equal([newGuid]);
      mockDapp.connect(account);
      // We don't really care about the value here, just that it is successful
      await manager.ensureSuccess(mockDapp.set_number(56));
    });

    it("Shouldn't be possible to recover the signer twice", async function () {
      const { account } = await deployOldAccountWithProxy();

      await upgradeAccount(account, argentAccountClassHash, []);

      const { account: otherAccount } = await deployAccount();
      // Recover the signer for the first time
      await otherAccount.execute({
        contractAddress: account.address,
        entrypoint: "recovery_from_legacy_upgrade",
        calldata: [],
      });
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      // Trying to recover the signer a second time
      await otherAccount
        .execute({
          contractAddress: account.address,
          entrypoint: "recovery_from_legacy_upgrade",
          calldata: [],
        })
        .should.be.rejectedWith("argent/no-signer-to-recover");
    });

    it("Shouldn't be possible to recover the signer an account that was correctly upgraded", async function () {
      const { account } = await deployOldAccountWithProxy();
      await upgradeAccount(account, argentAccountClassHash, ["0"]);

      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      const { account: otherAccount } = await deployAccount();
      await otherAccount
        .execute({
          contractAddress: account.address,
          entrypoint: "recovery_from_legacy_upgrade",
          calldata: [],
        })
        .should.be.rejectedWith("argent/no-signer-to-recover");
    });
  });

  describe("Testing upgrade version 0.4.0 with every signer type", function () {
    const nonStarknetKeyPairs = [
      { name: "Ethereum signature", keyPair: randomEthKeyPair },
      { name: "Secp256r1 signature", keyPair: randomSecp256r1KeyPair },
      { name: "Eip191 signature", keyPair: randomEip191KeyPair },
      { name: "Webauthn signature", keyPair: randomWebauthnLegacyOwner },
    ];

    for (const { name, keyPair } of nonStarknetKeyPairs) {
      it(`[${name}] Testing upgrade`, async function () {
        const owner = keyPair();
        const { account, guardian } = await deployAccount({ owner, classHash: classHashV040 });

        await upgradeAccount(account, argentAccountClassHash);
        expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

        mockDapp.connect(account);
        // We have to update the owner with the new webauthn format
        if (owner instanceof LegacyWebauthnOwner) {
          account.signer = new ArgentSigner(new WebauthnOwner(owner.getPrivateKey()), guardian);
        }
        await manager.ensureSuccess(mockDapp.set_number(42));
      });

      it(`[${name}] Testing upgrade without guardian ${name}`, async function () {
        const owner = keyPair();
        const { account } = await deployAccountWithoutGuardians({ owner, classHash: classHashV040 });

        await upgradeAccount(account, argentAccountClassHash);
        expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

        mockDapp.connect(account);
        // We have to update the owner with the new webauthn format
        if (owner instanceof LegacyWebauthnOwner) {
          account.signer = new ArgentSigner(new WebauthnOwner(owner.getPrivateKey()));
        }
        await manager.ensureSuccess(mockDapp.set_number(42));
      });
    }
  });
});
