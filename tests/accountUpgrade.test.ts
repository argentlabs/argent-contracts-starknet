import { expect } from "chai";
import { Contract } from "starknet";
import {
  declareContract,
  deployAccount,
  deployOldAccount,
  deployer,
  getUpgradeDataLegacy,
  loadContract,
  provider,
  upgradeAccount,
  declareContractFixtures
} from "./lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let argentAccountFutureClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;
  let testDappClassHash: string;
  let testDapp: Contract;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    // This is the same as ArgentAccount but with a different version (to have another class hash)
    // Done to be able to test upgradability
    argentAccountFutureClassHash = await declareContractFixtures("ArgentAccountFutureVersion");
    oldArgentAccountClassHash = await declareContractFixtures("OldArgentAccount");
    proxyClassHash = await declareContractFixtures("Proxy");
    testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it("Upgrade cairo 0 to current version", async function () {
    const { account } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
    await upgradeAccount(account, argentAccountClassHash, ["0"]);
    const newClashHash = await provider.getClassHashAt(account.address);
    expect(BigInt(newClashHash)).to.equal(BigInt(argentAccountClassHash));
  });

  it("Upgrade cairo 0 to cairo 1 with multicall", async function () {
    const { account } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
    await upgradeAccount(
      account,
      argentAccountClassHash,
      getUpgradeDataLegacy([testDapp.populateTransaction.set_number(42)]),
    );
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await testDapp.get_number(account.address).should.eventually.equal(42n);
  });

  it("Upgrade from current version FutureVersion", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    await upgradeAccount(account, argentAccountFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountFutureClassHash));
  });

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    await upgradeAccount(account, "0x01").should.be.rejectedWith("Class with hash 0x1 is not declared");
    await upgradeAccount(account, testDappClassHash).should.be.rejectedWith(
      `Entry point 0xfe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283 not found in contract with class hash ${testDappClassHash}`,
    );
  });
});
