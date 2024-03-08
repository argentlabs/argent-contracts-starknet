import { expect } from "chai";
import {
  declareContract,
  deployAccount,
  deployOldAccount,
  deployContract,
  getUpgradeDataLegacy,
  provider,
  upgradeAccount,
  declareFixtureContract,
  expectEvent,
  ContractWithClassHash,
  expectRevertWithErrorMessage,
  LegacyArgentSigner,
  deployLegacyAccount,
  StarknetKeyPair,
} from "./lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClassHash;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    mockDapp = await deployContract("MockDapp");
  });

  it("Upgrade cairo 0 to current version", async function () {
    const { account, owner } = await deployOldAccount();
    const receipt = await upgradeAccount(account, argentAccountClassHash, ["0"]);
    const newClashHash = await provider.getClassHashAt(account.address);
    expect(BigInt(newClashHash)).to.equal(BigInt(argentAccountClassHash));
    const newOwner = new StarknetKeyPair(owner.privateKey);
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerAdded",
      additionalKeys: [newOwner.guid.toString()],
    });
  });

  it("Upgrade cairo 0 to cairo 1 with multicall", async function () {
    const { account, owner } = await deployOldAccount();
    const receipt = await upgradeAccount(
      account,
      argentAccountClassHash,
      getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(42)]),
    );
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await mockDapp.get_number(account.address).should.eventually.equal(42n);
    const newOwner = new StarknetKeyPair(owner.privateKey);
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerAdded",
      additionalKeys: [newOwner.guid.toString()],
    });
  });

  it("Upgrade from 0.3.0 to Current Version", async function () {
    const { account } = await deployLegacyAccount(await declareFixtureContract("ArgentAccount-0.3.0"));
    await upgradeAccount(account, argentAccountClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
  });

  it("Upgrade from current version FutureVersion", async function () {
    // This is the same as ArgentAccount but with a different version (to have another class hash)
    const argentAccountFutureClassHash = await declareFixtureContract("ArgentAccountFutureVersion");
    const { account } = await deployAccount();

    await upgradeAccount(account, argentAccountFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountFutureClassHash));
  });

  it("Shouldn't be possible to upgrade if an owner escape is ongoing", async function () {
    const classHash = await declareFixtureContract("ArgentAccount-0.3.0");
    const { account, accountContract, owner, guardian } = await deployLegacyAccount(classHash);

    account.signer = guardian;
    await accountContract.trigger_escape_owner(12);

    account.signer = new LegacyArgentSigner(owner, guardian);
    await expectRevertWithErrorMessage("argent/ready-at-shoud-be-null", () =>
      upgradeAccount(account, argentAccountClassHash),
    );
  });

  it("Shouldn't be possible to upgrade if a guardian escape is ongoing", async function () {
    const classHash = await declareFixtureContract("ArgentAccount-0.3.0");
    const { account, accountContract, owner, guardian } = await deployLegacyAccount(classHash);

    account.signer = owner;
    await accountContract.trigger_escape_guardian(12);

    account.signer = new LegacyArgentSigner(owner, guardian);
    await expectRevertWithErrorMessage("argent/ready-at-shoud-be-null", () =>
      upgradeAccount(account, argentAccountClassHash),
    );
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
});
