import { expect } from "chai";
import { CairoOption, CairoOptionVariant, Contract } from "starknet";
import {
  ArgentSigner,
  ContractWithClass,
  LegacyStarknetKeyPair,
  RawSigner,
  StarknetKeyPair,
  deployAccount,
  deployAccountWithoutGuardian,
  deployLegacyAccount,
  deployLegacyAccountWithoutGuardian,
  deployOldAccountWithProxy,
  expectEvent,
  expectRevertWithErrorMessage,
  getUpgradeDataLegacy,
  manager,
  randomStarknetKeyPair,
  upgradeAccount,
} from "../lib";

describe.only("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;
  const upgradeData: any[] = [];

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.deployContract("MockDapp");
    const v030 = "0.3.0";
    const classHashV030 = await manager.declareArtifactAccountContract(v030);
    upgradeData.push({
      name: v030,
      deployAccount: async () => deployLegacyAccount(classHashV030),
      deployAccountWithoutGuardian: async () => deployLegacyAccountWithoutGuardian(classHashV030),
      triggerEscapeOwner: async (accountContract: Contract) => accountContract.trigger_escape_owner(12),
      triggerEscapeGuardian: async (accountContract: Contract) => accountContract.trigger_escape_guardian(12),
    });

    const v031 = "0.3.1";
    const classHashV031 = await manager.declareArtifactAccountContract(v031);
    upgradeData.push({
      name: v031,
      deployAccount: async () => deployLegacyAccount(classHashV031),
      deployAccountWithoutGuardian: async () => deployLegacyAccountWithoutGuardian(classHashV031),
      triggerEscapeOwner: async (accountContract: Contract) => accountContract.trigger_escape_owner(12),
      triggerEscapeGuardian: async (accountContract: Contract) => accountContract.trigger_escape_guardian(12),
    });

    const v040 = "0.4.0";
    const classHashV040 = await manager.declareArtifactAccountContract(v040);
    upgradeData.push({
      name: v040,
      deployAccount: async () => deployAccount({ classHash: classHashV040 }),
      deployAccountWithoutGuardian: async () => deployAccountWithoutGuardian({ classHash: classHashV040 }),
      triggerEscapeOwner: async (accountContract: Contract) => accountContract.trigger_escape_owner(randomStarknetKeyPair().compiledSigner),
      triggerEscapeGuardian: async (accountContract: Contract) => accountContract.trigger_escape_guardian(new CairoOption(CairoOptionVariant.None)),
    });
  });

  it("Upgrade cairo 0 to current version", async function () {
    // TODO Try to incorporate old account with proxy in the upgradeData array
    const { account } = await deployOldAccountWithProxy();
    await upgradeAccount(account, argentAccountClassHash, ["0"]);
    const newClashHash = await manager.getClassHashAt(account.address);
    expect(BigInt(newClashHash)).to.equal(BigInt(argentAccountClassHash));
  });

  it("Upgrade cairo 0 to cairo 1 with multicall", async function () {
    const { account } = await deployOldAccountWithProxy();
    await upgradeAccount(
      account,
      argentAccountClassHash,
      getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(42)]),
    );
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });

  it("Waiting for upgradeData to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const { name, deployAccount, triggerEscapeOwner, triggerEscapeGuardian, deployAccountWithoutGuardian } of upgradeData) {
        it(`Should be possible to upgrade from ${name}`, async function () {
          const { account } = await deployAccount();
          await upgradeAccount(account, argentAccountClassHash);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
        });

        it(`Should be possible to upgrade without guardian from ${name}`, async function () {
          const { account } = await deployAccountWithoutGuardian();
          await upgradeAccount(account, argentAccountClassHash);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
        });

        it(`Should be possible to upgrade if an owner escape is ongoing from ${name}`, async function () {
          const { account, accountContract, guardian } = await deployAccount();

          const oldSigner = account.signer;

          account.signer = toSigner(guardian);
          await triggerEscapeOwner(accountContract);

          account.signer = oldSigner;
          await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
            from_address: account.address,
            eventName: "EscapeCanceled",
          });
        });

        it(`Should be possible to upgrade if a guardian escape is ongoing from ${name}`, async function () {
          const { account, accountContract, owner } = await deployAccount();

          const oldSigner = account.signer;
          account.signer = toSigner(owner);

          await triggerEscapeGuardian(accountContract);

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
      "Entry point EntryPointSelector(0xfe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283) not found in contract.",
    );
  });

  it("Shouldn't upgrade from current version to itself", async function () {
    const { account } = await deployAccount();
    await expectRevertWithErrorMessage("argent/downgrade-not-allowed", upgradeAccount(account, argentAccountClassHash));
  });
});

function toSigner(signer: RawSigner): RawSigner {
  if (signer instanceof LegacyStarknetKeyPair) {
    return signer;
  } else if (signer instanceof StarknetKeyPair) {
    return new ArgentSigner(signer);
  } else {
    throw new Error("unsupported Signer type");
  }
}
