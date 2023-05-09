import { expect } from "chai";
import { shortString } from "starknet";
import { declareContract, deployAccount, deployOldAccount, provider, upgradeAccount } from "./shared";

describe("Test Argent Account: upgrade", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;
  let argentAccountV1ClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    // This is the same as ArgentAccount but with a different version (to have another class hash)
    // Done to be able to test upgradability ()
    argentAccountV1ClassHash = await declareContract("ArgentAccountV1");
    oldArgentAccountClassHash = await declareContract("OldArgentAccount");
    proxyClassHash = await declareContract("Proxy");
  });

  it("Should be posssible to deploy an argent account version 0.2.4 and upgrade it to cairo 1 version 0.3.0", async function () {
    const accountToUpgrade = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
    const initialVersion = await provider.callContract({
      contractAddress: accountToUpgrade.address,
      entrypoint: "getVersion",
    });
    expect(shortString.decodeShortString(initialVersion.result[0])).to.equal("0.2.4");

    await upgradeAccount(accountToUpgrade, argentAccountClassHash);

    const newVersion = await provider.callContract({
      contractAddress: accountToUpgrade.address,
      entrypoint: "get_version",
    });
    expect(shortString.decodeShortString(newVersion.result[0])).to.equal("0");
    expect(shortString.decodeShortString(newVersion.result[1])).to.equal("3");
    expect(shortString.decodeShortString(newVersion.result[2])).to.equal("0");
  });

  it("Should be possible to upgrade an account from version 0.3.0 to 0.3.1", async function () {
    const account = await deployAccount(argentAccountClassHash);
    const currentVersion = await provider.callContract({
      contractAddress: account.address,
      entrypoint: "get_version",
    });
    expect(shortString.decodeShortString(currentVersion.result[0])).to.equal("0");
    expect(shortString.decodeShortString(currentVersion.result[1])).to.equal("3");
    expect(shortString.decodeShortString(currentVersion.result[2])).to.equal("0");
    await upgradeAccount(account, argentAccountV1ClassHash, "1");
    const newVersion = await provider.callContract({
      contractAddress: account.address,
      entrypoint: "get_version",
    });
    expect(shortString.decodeShortString(newVersion.result[0])).to.equal("0");
    expect(shortString.decodeShortString(newVersion.result[1])).to.equal("3");
    expect(shortString.decodeShortString(newVersion.result[2])).to.equal("1");
  });
});
