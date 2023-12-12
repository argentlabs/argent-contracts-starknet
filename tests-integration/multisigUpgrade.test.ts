import { expect } from "chai";
import { declareContract, provider, upgradeAccount, declareFixtureContract, restartDevnetIfTooLong } from "./lib";
import { deployMultisig } from "./lib/multisig";

describe("ArgentMultisig: upgrade", function () {
  let argentMultisig: string;
  let argentMultisigFutureClassHash: string;
  let testDappClassHash: string;

  before(async () => {
    await restartDevnetIfTooLong();
    argentMultisig = await declareContract("ArgentMultisig");
    // This is the same as Argent Multisig but with a different version (to have another class hash)
    // Done to be able to test upgradability
    argentMultisigFutureClassHash = await declareFixtureContract("ArgentMultisigFutureVersion");
    testDappClassHash = await declareContract("TestDapp");
  });

  it("Upgrade from current version to FutureVersionMultisig", async function () {
    const threshold = 1;
    const signersLength = 1;
    const { account } = await deployMultisig(argentMultisig, threshold, signersLength);
    await upgradeAccount(account, argentMultisigFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentMultisigFutureClassHash));
  });

  it("Reject invalid upgrade targets", async function () {
    const threshold = 1;
    const signersLength = 1;
    const { account } = await deployMultisig(argentMultisig, threshold, signersLength);
    await upgradeAccount(account, "0x01").should.be.rejectedWith(
      `Class with hash ClassHash(\\n    StarkFelt(\\n        \\"0x0000000000000000000000000000000000000000000000000000000000000001\\",\\n    ),\\n) is not declared`,
    );
    await upgradeAccount(account, testDappClassHash).should.be.rejectedWith(
      `EntryPointSelector(StarkFelt(\\"0x00fe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283\\")) not found in contract`,
    );
  });
});
