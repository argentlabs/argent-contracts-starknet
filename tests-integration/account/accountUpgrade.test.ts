import { expect } from "chai";
import { Account, CairoOption, CairoOptionVariant, CallData, Contract, hash, RawArgs } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  ContractWithClass,
  deployAccount,
  deployAccountWithoutGuardians,
  deployLegacyAccount,
  deployLegacyAccountWithoutGuardian,
  expectEvent,
  expectRevertWithErrorMessage,
  fundAccount,
  generateRandomNumber,
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
  triggerEscapeOwnerCall: SelfCall;
  triggerEscapeGuardianCall: SelfCall;
}

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;
  let classHashV040: string;
  const upgradeData: UpgradeDataEntry[] = [];
  let randomNumber: bigint;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.declareAndDeployContract("MockDapp");

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

    // From here on we begin support for V3 transactions
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

  beforeEach(async () => {
    randomNumber = generateRandomNumber();
  });

  it("Waiting for upgradeData to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const {
        name,
        deployAccount,
        triggerEscapeOwnerCall,
        triggerEscapeGuardianCall,
        deployAccountWithoutGuardians,
      } of upgradeData) {
        it(`[${name}] Should be possible to upgrade `, async function () {
          const { account } = await deployAccount();
          const txReceipt = await upgradeAccount(account, argentAccountClassHash);
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
          const accountV3 = await getAccountV3(account);
          mockDapp.providerOrAccount = accountV3;
          // This should work as long as we support the "old" signature format [r1, s1, r2, s2]
          await manager.ensureSuccess(mockDapp.set_number(randomNumber));
        });

        it(`[${name}] Should be possible to upgrade without guardian from ${name}`, async function () {
          const { account } = await deployAccountWithoutGuardians();
          await upgradeAccount(account, argentAccountClassHash);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          const accountV3 = await getAccountV3(account);
          mockDapp.providerOrAccount = accountV3;
          await manager.ensureSuccess(mockDapp.set_number(randomNumber));
        });

        it(`[${name}] Upgrade cairo with multicall`, async function () {
          const { account } = await deployAccount();
          const upgradeData = account.cairoVersion
            ? CallData.compile([[mockDapp.populateTransaction.set_number(randomNumber)]])
            : getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(randomNumber)]);
          await upgradeAccount(account, argentAccountClassHash, upgradeData);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          await mockDapp.get_number(account.address).should.eventually.equal(randomNumber);
          // We don't really care about the value here, just that it is successful
          const accountV3 = await getAccountV3(account);
          mockDapp.providerOrAccount = accountV3;
          await manager.ensureSuccess(mockDapp.set_number(randomNumber));
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
          await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
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
          await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
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

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployAccount();

    await upgradeAccount(account, "0x1").should.be.rejectedWith(
      "Class with hash 0x0000000000000000000000000000000000000000000000000000000000000001 is not declared.",
    );

    await upgradeAccount(account, mockDapp.classHash).should.be.rejectedWith(
      "(0x617267656e742f6d756c746963616c6c2d6661696c6564 ('argent/multicall-failed'), 0x0 (''), 0x454e545259504f494e545f4e4f545f464f554e44 ('ENTRYPOINT_NOT_FOUND'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED')).",
    );
  });

  it("Shouldn't upgrade from current version to itself", async function () {
    const { account } = await deployAccount();
    await expectRevertWithErrorMessage("argent/downgrade-not-allowed", upgradeAccount(account, argentAccountClassHash));
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

        const accountV3 = await getAccountV3(account);
        mockDapp.providerOrAccount = accountV3;
        // We have to update the owner with the new webauthn format
        if (owner instanceof LegacyWebauthnOwner) {
          accountV3.signer = new ArgentSigner(new WebauthnOwner(owner.getPrivateKey()), guardian);
        }
        await manager.ensureSuccess(mockDapp.set_number(randomNumber));
      });

      it(`[${name}] Testing upgrade without guardian ${name}`, async function () {
        const owner = keyPair();
        const { account } = await deployAccountWithoutGuardians({ owner, classHash: classHashV040 });

        await upgradeAccount(account, argentAccountClassHash);
        expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

        const accountV3 = await getAccountV3(account);
        mockDapp.providerOrAccount = accountV3;
        // We have to update the owner with the new webauthn format
        if (owner instanceof LegacyWebauthnOwner) {
          accountV3.signer = new ArgentSigner(new WebauthnOwner(owner.getPrivateKey()));
        }
        await manager.ensureSuccess(mockDapp.set_number(randomNumber));
      });
    }
  });
});

async function getAccountV3(account: Account): Promise<Account> {
  await fundAccount(account.address, 1e18, "STRK");
  return new ArgentAccount({ provider: manager, address: account.address, signer: account.signer });
}
