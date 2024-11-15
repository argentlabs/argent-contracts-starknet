import { expect } from "chai";
import { CairoOption, CairoOptionVariant } from "starknet";
import {
  ArgentSigner,
  ContractWithClass,
  deployAccount,
  deployLegacyAccount,
  deployOldAccountWithProxy,
  expectEvent,
  expectRevertWithErrorMessage,
  getUpgradeDataLegacy,
  manager,
  randomStarknetKeyPair,
  upgradeAccount,
} from "../lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;

  const upgradeData: any[] = [];
  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.deployContract("MockDapp");
    const classHashV030 = await manager.declareArtifactContract(
      "/account-0.3.0-0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003/ArgentAccount",
    );
    upgradeData.push({
      deployAccount: async () => deployLegacyAccount(classHashV030),
      newOwner: 12,
      newGuardian: 12,
      toSigner: (x: any) => x,
    });

    const classHashV031 = await manager.declareArtifactContract(
      "/account-0.3.1-0x29927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b/ArgentAccount",
    );
    upgradeData.push({
      deployAccount: async () => deployLegacyAccount(classHashV031),
      newOwner: 12,
      newGuardian: 12,
      toSigner: (x: any) => x,
    });

    const classHashV040 = await manager.declareArtifactContract(
      "/account-0.4.0-0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f/ArgentAccount",
    );
    upgradeData.push({
      deployAccount: async () => deployAccount({ classHash: classHashV040 }),
      newOwner: randomStarknetKeyPair().compiledSigner,
      newGuardian: new CairoOption(CairoOptionVariant.None),
      toSigner: (x: any) => new ArgentSigner(x),
    });
  });

  it("Upgrade cairo 0 to current version", async function () {
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
      for (const { deployAccount, newOwner, newGuardian, toSigner } of upgradeData) {
        it("Should be possible to upgrade", async function () {
          const { account } = await deployAccount();
          await upgradeAccount(account, argentAccountClassHash);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
        });

        it("Should be possible to upgrade if an owner escape is ongoing", async function () {
          const { account, accountContract, guardian } = await deployAccount();

          const oldSigner = account.signer;
          account.signer = toSigner(guardian);
          await accountContract.trigger_escape_owner(newOwner);

          account.signer = oldSigner;
          await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
            from_address: account.address,
            eventName: "EscapeCanceled",
          });
        });

        it("Should be possible to upgrade if a guardian escape is ongoing", async function () {
          const { account, accountContract, owner } = await deployAccount();

          const oldSigner = account.signer;
          account.signer = toSigner(owner);

          await accountContract.trigger_escape_guardian(newGuardian);

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
