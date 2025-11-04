import { expect } from "chai";
import { Account, ETransactionVersion, hash } from "starknet";
import {
  ArgentAccount,
  ContractWithClass,
  deployAccount,
  deployOldAccountWithProxy,
  deployOldAccountWithProxyWithoutGuardian,
  expectEvent,
  expectRevertWithErrorMessage,
  generateRandomNumber,
  getUpgradeDataLegacy,
  manager,
  StarknetKeyPair,
  upgradeAccount,
} from "../lib";

// I recommend using the "only" keyword and run each test individually to avoid running into some issues

describe("ArgentAccount: testing 0.2.3.1 upgrade", function () {
  const argentAccountClassHash = "0x073414441639dcd11d1846f287650a00c60c416b9d3ba45d31c651672125b2c2";
  const upgradeExtraCalldata = ["0"];
  let mockDapp: ContractWithClass;
  let randomNumber: bigint;

  before(async () => {
    mockDapp = await manager.loadContract("0x20e4fb45e1ada8b9ea95e96dd2fa87056fe852bb6408769f0e19c8f9c39531c");
  });

  beforeEach(async () => {
    randomNumber = generateRandomNumber();
  });

  it(`[0.2.3.1] Should be possible to upgrade `, async function () {
    const { account } = await deployOldAccountWithProxy();
    const txReceipt = await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata);
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    // Check events
    const eventsEmittedByAccount = txReceipt.events.filter((e) => e.from_address === account.address);

    const expectedEvents = [
      "OwnerAddedGuid",
      "GuardianAddedGuid",
      "transaction_executed",
      "account_upgraded",
      "SignerLinked",
      "SignerLinked",
    ];

    const missingEvents = [];
    for (const expectedEventName of expectedEvents) {
      const eventIndex = eventsEmittedByAccount.findIndex(
        (event) => event.keys?.[0] === hash.getSelectorFromName(expectedEventName),
      );
      if (eventIndex === -1) {
        missingEvents.push(expectedEventName);
      } else {
        eventsEmittedByAccount.splice(eventIndex, 1);
      }
    }
    expect(missingEvents).to.have.lengthOf(0, `Expected events ${missingEvents.join(", ")} not found`);
    expect(eventsEmittedByAccount).to.have.lengthOf(0, `Unexpected events ${eventsEmittedByAccount.join(", ")} found`);
    const accountV3 = getAccountV3(account);
    mockDapp.providerOrAccount = accountV3;
    const call = mockDapp.populateTransaction.set_number(randomNumber);
    // This should work as long as we support the "old" signature format [r1, s1, r2, s2]
    await manager.ensureSuccess(accountV3.execute(call));
  });

  it(`[0.2.3.1] Should be possible to upgrade without guardian`, async function () {
    const { account } = await deployOldAccountWithProxyWithoutGuardian();
    await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata);
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    const accountV3 = getAccountV3(account);
    mockDapp.providerOrAccount = accountV3;

    const call = mockDapp.populateTransaction.set_number(randomNumber);
    await manager.ensureSuccess(accountV3.execute(call));
  });

  it(`[0.2.3.1] Upgrade cairo with multicall`, async function () {
    const { account } = await deployOldAccountWithProxy();
    const upgradeData = getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(randomNumber)]);
    await upgradeAccount(account, argentAccountClassHash, upgradeData);
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await mockDapp.get_number(account.address).should.eventually.equal(randomNumber);

    const accountV3 = getAccountV3(account);
    mockDapp.providerOrAccount = accountV3;
    const call = mockDapp.populateTransaction.set_number(randomNumber);
    // We don't really care about the value here, just that it is successful
    await manager.ensureSuccess(accountV3.execute(call));
  });

  it(`[0.2.3.1] Should be possible to upgrade if an owner escape is ongoing`, async function () {
    const { account, guardian } = await deployOldAccountWithProxy();

    const oldSigner = account.signer;
    account.signer = guardian;

    await manager.ensureSuccess(
      account.execute({
        contractAddress: account.address,
        entrypoint: "triggerEscapeSigner",
      }),
    );

    account.signer = oldSigner;
    await expectEvent(await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata), {
      from_address: account.address,
      eventName: "EscapeCanceled",
    });
  });

  it(`[0.2.3.1] Should be possible to upgrade if a guardian escape is ongoing`, async function () {
    const { account, owner } = await deployOldAccountWithProxy();

    const oldSigner = account.signer;
    account.signer = owner;

    await manager.ensureSuccess(
      account.execute({
        contractAddress: account.address,
        entrypoint: "triggerEscapeGuardian",
      }),
    );

    account.signer = oldSigner;
    await expectEvent(await upgradeAccount(account, argentAccountClassHash, upgradeExtraCalldata), {
      from_address: account.address,
      eventName: "EscapeCanceled",
    });
  });

  describe("Testing recovery_from_legacy_upgrade when upgrading from 0.2.3", function () {
    it("Should be possible to recover the signer", async function () {
      const { account, owner } = await deployOldAccountWithProxy();
      const legacyClassHash = await manager.getClassHashAt(account.address);
      await upgradeAccount(account, argentAccountClassHash, []);

      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(legacyClassHash));
      const accountV3 = getAccountV3(account);
      mockDapp.providerOrAccount = accountV3;
      // Check the account is in the wrong state
      const wrongGuids = await account.callContract({
        contractAddress: account.address,
        entrypoint: "get_owners_guids",
      });
      // Since we have to do a raw call, we have the unparsed value returned
      expect(wrongGuids.length).to.equal(1);
      expect(wrongGuids[0]).to.equal("0x0");
      await expectRevertWithErrorMessage("argent/no-single-stark-owner", mockDapp.set_number(randomNumber));

      const { account: otherAccount } = await deployAccount({ fundingAmount: 5e16 });
      // Recover the signer
      const callRecovery = {
        contractAddress: account.address,
        entrypoint: "recovery_from_legacy_upgrade",
        calldata: [],
      };
      await manager.ensureSuccess(otherAccount.execute(callRecovery));
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      // Making sure it has the new owner migrated correctly
      const newAccountContract = await manager.loadContract(account.address);
      const newGuid = new StarknetKeyPair(owner.privateKey).guid;
      expect(await newAccountContract.get_owners_guids()).to.deep.equal([newGuid]);

      const call = mockDapp.populateTransaction.set_number(randomNumber);
      // We don't really care about the value here, just that it is successful
      await manager.ensureSuccess(accountV3.execute(call));
    });

    it("Shouldn't be possible to recover the signer twice", async function () {
      const { account } = await deployOldAccountWithProxy();

      await upgradeAccount(account, argentAccountClassHash, []);

      const { account: otherAccount } = await deployAccount({ fundingAmount: 8e16 });
      // Recover the signer
      const callRecovery = {
        contractAddress: account.address,
        entrypoint: "recovery_from_legacy_upgrade",
        calldata: [],
      };
      await manager.ensureSuccess(otherAccount.execute(callRecovery));
      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
      // Trying to recover the signer a second time
      await otherAccount.execute(callRecovery).should.be.rejectedWith("argent/no-signer-to-recover");
    });

    it("Shouldn't be possible to recover the signer an account that was correctly upgraded", async function () {
      const { account } = await deployOldAccountWithProxy();
      await upgradeAccount(account, argentAccountClassHash, ["0"]);

      expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

      const { account: otherAccount } = await deployOldAccountWithProxy();
      await otherAccount
        .execute({
          contractAddress: account.address,
          entrypoint: "recovery_from_legacy_upgrade",
          calldata: [],
        })
        .should.be.rejectedWith("argent/no-signer-to-recover");
    });
  });
});

function getAccountV3(account: Account): ArgentAccount {
  return new ArgentAccount({
    provider: manager,
    address: account.address,
    signer: account.signer,
    cairoVersion: "1",
    transactionVersion: ETransactionVersion.V3,
  });
}
