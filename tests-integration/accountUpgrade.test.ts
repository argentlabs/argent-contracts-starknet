import { expect } from "chai";
import {
  ContractWithClass,
  LegacyArgentSigner,
  deployAccount,
  deployLegacyAccount,
  deployOldAccount,
  expectEvent,
  expectRevertWithErrorMessage,
  getUpgradeDataLegacy,
  provider,
  upgradeAccount,
} from "../lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;

  before(async () => {
    argentAccountClassHash = await provider.declareLocalContract("ArgentAccount");
    mockDapp = await provider.deployContract("MockDapp");
  });

  it("Upgrade cairo 0 to current version", async function () {
    const { account } = await deployOldAccount();
    await upgradeAccount(account, argentAccountClassHash, ["0"]);
    const newClashHash = await provider.getClassHashAt(account.address);
    expect(BigInt(newClashHash)).to.equal(BigInt(argentAccountClassHash));
  });

  it("Upgrade cairo 0 to cairo 1 with multicall", async function () {
    const { account } = await deployOldAccount();
    await upgradeAccount(
      account,
      argentAccountClassHash,
      getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(42)]),
    );
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });

  it("Upgrade from 0.3.0 to Current Version", async function () {
    const { account } = await deployLegacyAccount(await provider.declareFixtureContract("ArgentAccount-0.3.0"));
    await upgradeAccount(account, argentAccountClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
  });

  it("Upgrade from current version FutureVersion", async function () {
    const argentAccountFutureClassHash = await provider.declareLocalContract("MockFutureArgentAccount");
    const { account } = await deployAccount();

    const response = await upgradeAccount(account, argentAccountFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountFutureClassHash));

    const data = [argentAccountFutureClassHash];
    await expectEvent(response, { from_address: account.address, eventName: "AccountUpgraded", data });
  });

  it("Should be possible to upgrade if an owner escape is ongoing", async function () {
    const classHash = await provider.declareFixtureContract("ArgentAccount-0.3.0");
    const { account, accountContract, owner, guardian } = await deployLegacyAccount(classHash);

    account.signer = guardian;
    await accountContract.trigger_escape_owner(12);

    account.signer = new LegacyArgentSigner(owner, guardian);
    await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
      from_address: account.address,
      eventName: "EscapeCanceled",
    });
  });

  it("Should be possible to upgrade if a guardian escape is ongoing", async function () {
    const classHash = await provider.declareFixtureContract("ArgentAccount-0.3.0");
    const { account, accountContract, owner, guardian } = await deployLegacyAccount(classHash);

    account.signer = owner;
    await accountContract.trigger_escape_guardian(12);

    account.signer = new LegacyArgentSigner(owner, guardian);
    await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
      from_address: account.address,
      eventName: "EscapeCanceled",
    });
  });

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployAccount();
    await upgradeAccount(account, "0x01").should.be.rejectedWith(
      `Class with hash ClassHash(\\n    StarkFelt(\\n        \\"0x0000000000000000000000000000000000000000000000000000000000000001\\",\\n    ),\\n) is not declared`,
    );
    await upgradeAccount(account, mockDapp.classHash).should.be.rejectedWith(
      `EntryPointSelector(StarkFelt(\\"0x00fe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283\\")) not found in contract`,
    );
  });

  it("Shouldn't upgrade from current version to itself", async function () {
    const { account } = await deployAccount();
    await expectRevertWithErrorMessage("argent/downgrade-not-allowed", () =>
      upgradeAccount(account, argentAccountClassHash),
    );
  });
});
