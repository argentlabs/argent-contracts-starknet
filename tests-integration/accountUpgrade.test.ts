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
} from "./lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let testDapp: ContractWithClassHash;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    testDapp = await deployContract("TestDapp");
  });

  it("Upgrade cairo 0 to current version", async function () {
    const { account, owner } = await deployOldAccount();
    const receipt = await upgradeAccount(account, argentAccountClassHash, ["0"]);
    const newClashHash = await provider.getClassHashAt(account.address);
    expect(BigInt(newClashHash)).to.equal(BigInt(argentAccountClassHash));
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerAdded",
      additionalKeys: [owner.publicKey.toString()],
    });
  });

  it("Upgrade cairo 0 to cairo 1 with multicall", async function () {
    const { account, owner } = await deployOldAccount();
    const receipt = await upgradeAccount(
      account,
      argentAccountClassHash,
      getUpgradeDataLegacy([testDapp.populateTransaction.set_number(42)]),
    );
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await testDapp.get_number(account.address).should.eventually.equal(42n);
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerAdded",
      additionalKeys: [owner.publicKey.toString()],
    });
  });

  it("Upgrade from 0.3.0 to Current Version", async function () {
    const { account } = await deployAccount({ classHash: await declareFixtureContract("ArgentAccount-0.3.0") });
    // TODO Can use what I did in escape packing
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

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployAccount();
    await upgradeAccount(account, "0x01").should.be.rejectedWith(
      `Class with hash ClassHash(\\n    StarkFelt(\\n        \\"0x0000000000000000000000000000000000000000000000000000000000000001\\",\\n    ),\\n) is not declared`,
    );
    await upgradeAccount(account, testDapp.classHash).should.be.rejectedWith(
      `EntryPointSelector(StarkFelt(\\"0x00fe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283\\")) not found in contract`,
    );
  });
});
