import { expect } from "chai";
import { num, shortString } from "starknet";
import { declareContract, deployAccount, deployOldAccount, provider, upgradeAccount } from "./shared";

describe("Argent Account: upgrade", function () {
  let argentAccountClassHash: string;
  let argentAccountFutureClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    // This is the same as ArgentAccount but with a different version (to have another class hash)
    // Done to be able to test upgradability
    argentAccountFutureClassHash = await declareContract("ArgentAccountFutureVersion");
    oldArgentAccountClassHash = await declareContract("OldArgentAccount");
    proxyClassHash = await declareContract("Proxy");
  });

  it("Should be posssible to deploy an argent account version 0.2.4 and upgrade it to cairo 1 version 0.3.0", async function () {
    const { account: accountToUpgrade } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
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
    expect(newVersion.result[0]).to.equal(num.toHex(0));
    expect(newVersion.result[1]).to.equal(num.toHex(3));
    expect(newVersion.result[2]).to.equal(num.toHex(0));
  });

  it("Should be possible to upgrade an account from version 0.3.0 to FutureVersion", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    const currentVersion = await provider.callContract({
      contractAddress: account.address,
      entrypoint: "get_version",
    });
    expect(currentVersion.result[0]).to.equal(num.toHex(0));
    expect(currentVersion.result[1]).to.equal(num.toHex(3));
    expect(currentVersion.result[2]).to.equal(num.toHex(0));
    await upgradeAccount(account, argentAccountFutureClassHash);
    const newVersion = await provider.callContract({
      contractAddress: account.address,
      entrypoint: "get_version",
    });
    expect(newVersion.result[0]).to.equal(num.toHex(42));
    expect(newVersion.result[1]).to.equal(num.toHex(42));
    expect(newVersion.result[2]).to.equal(num.toHex(42));
  });
});