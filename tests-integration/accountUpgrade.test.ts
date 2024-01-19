import { expect } from "chai";
import { Account, CallData, Contract, hash, num } from "starknet";
import {
  declareContract,
  deployAccount,
  deployOldAccount,
  deployer,
  getUpgradeDataLegacy,
  loadContract,
  provider,
  upgradeAccount,
  declareFixtureContract,
  expectEvent,
  expectRevertWithErrorMessage,
  ArgentSigner,
  randomKeyPair,
  fundAccount,
  LegacyMultisigSigner,
  LegacyKeyPair,
  LegacyArgentSigner,
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
    argentAccountFutureClassHash = await declareFixtureContract("ArgentAccountFutureVersion");
    oldArgentAccountClassHash = await declareFixtureContract("OldArgentAccount");
    proxyClassHash = await declareFixtureContract("Proxy");
    testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDapp = await loadContract(contract_address);
  });

  it("Upgrade cairo 0 to current version", async function () {
    const { account, owner } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
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
    const { account, owner } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
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

  it("Upgrade from current version FutureVersion", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    await upgradeAccount(account, argentAccountFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentAccountFutureClassHash));
  });

  it("Shouldn't be possible to upgrade if an owner escape is ongoing", async function () {
    const classHash = await declareFixtureContract("ArgentAccount-0.3.0");
    const owner = new LegacyKeyPair();
    const guardian = new LegacyKeyPair();
    const salt = num.toHex(randomKeyPair().privateKey);
    const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey });
    const contractAddress = hash.calculateContractAddressFromHash(
      salt,
      classHash,
      constructorCalldata,
      0,
    );
    await fundAccount(contractAddress, 1e15); // 0.001 ETH
    const account = new Account(provider, contractAddress, owner, "1");
    account.signer = new LegacyArgentSigner(owner, guardian);

    const { transaction_hash } = await account.deploySelf({
      classHash,
      constructorCalldata,
      addressSalt: salt,
    });
    await provider.waitForTransaction(transaction_hash);

    const accountContract = await loadContract(account.address);
    accountContract.connect(account);

    account.signer = guardian;
    await accountContract.trigger_escape_owner(12);

    account.signer = new LegacyArgentSigner(owner, guardian);
    await expectRevertWithErrorMessage("argent/ready-at-shoud-be-null", () =>
      upgradeAccount(account, argentAccountClassHash),
    );
  });

  it("Shouldn't be possible to upgrade if a guardian escape is ongoing", async function () {
    const classHash = await declareFixtureContract("ArgentAccount-0.3.0");
    const owner = new LegacyKeyPair();
    const guardian = new LegacyKeyPair();
    const salt = num.toHex(randomKeyPair().privateKey);
    const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey });
    const contractAddress = hash.calculateContractAddressFromHash(
      salt,
      classHash,
      constructorCalldata,
      0,
    );
    await fundAccount(contractAddress, 1e15); // 0.001 ETH
    const account = new Account(provider, contractAddress, owner, "1");
    account.signer = new LegacyArgentSigner(owner, guardian);

    const { transaction_hash } = await account.deploySelf({
      classHash,
      constructorCalldata,
      addressSalt: salt,
    });
    await provider.waitForTransaction(transaction_hash);

    const accountContract = await loadContract(account.address);
    accountContract.connect(account);

    account.signer = owner;
    await accountContract.trigger_escape_guardian(12);

    account.signer = new LegacyArgentSigner(owner, guardian);
    await expectRevertWithErrorMessage("argent/ready-at-shoud-be-null", () =>
      upgradeAccount(account, argentAccountClassHash),
    );
  });

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployAccount(argentAccountClassHash);
    await upgradeAccount(account, "0x01").should.be.rejectedWith("Class with hash 0x1 is not declared");
    await upgradeAccount(account, testDappClassHash).should.be.rejectedWith(
      `Entry point 0xfe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283 not found in contract with class hash ${testDappClassHash}`,
    );
  });
});
