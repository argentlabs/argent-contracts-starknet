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
  manager,
  upgradeAccount,
} from "../lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;

  // TODO check if fixtures folder still useful?
  // Should the discovery be automated by reading all folders names?
  const accountsToUpgradeFrom = [
    "/account-0.3.0-0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003/ArgentAccount",
    "/account-0.3.1-0x29927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b/ArgentAccount",
    // Doesn't work yet for this, gotta adapt the deploy logic
    // "/account-0.4.0-0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f/ArgentAccount",
  ];

  const x: any[] = [];
  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.deployContract("MockDapp");
    const ca1 = await manager.declareArtifactContract(
      "/account-0.3.0-0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003/ArgentAccount",
    );
    const deploy1 = async () => deployLegacyAccount(ca1);
    x.push({ classHash: ca1, deployFn: deploy1 });

    const ca2 = await manager.declareArtifactContract(
      "/account-0.3.0-0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003/ArgentAccount",
    );
    const deploy2 = async () => deployLegacyAccount(ca2);
    x.push({ classHash: ca2, deployFn: deploy2 });

    const ca3 = await manager.declareArtifactContract(
      "/account-0.3.0-0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003/ArgentAccount",
    );
    const deploy3 = async () => deployAccount({ classHash: ca3 });
    x.push({ classHash: ca3, deployFn: deploy3 });
  });

  it("Upgrade cairo 0 to current version", async function () {
    const { account } = await deployOldAccount();
    await upgradeAccount(account, argentAccountClassHash, ["0"]);
    const newClashHash = await manager.getClassHashAt(account.address);
    expect(BigInt(newClashHash)).to.equal(BigInt(argentAccountClassHash));
  });

  it("Upgrade cairo 0 to cairo 1 with multicall", async function () {
    const { account } = await deployOldAccount();
    await upgradeAccount(
      account,
      argentAccountClassHash,
      getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(42)]),
    );
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
    await mockDapp.get_number(account.address).should.eventually.equal(42n);
  });

  it.only("Waiting accounts to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const { deployFn } of x) {
        describe(`For $`, function () {
          it("Should be possible to upgrade", async function () {
            const { account } = await deployFn();
            await upgradeAccount(account, argentAccountClassHash);
            expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          });

          it("Should be possible to upgrade if an owner escape is ongoing", async function () {
            const { account, accountContract, owner, guardian } = await deployFn();

            account.signer = guardian;
            await accountContract.trigger_escape_owner(12);

            account.signer = new LegacyArgentSigner(owner, guardian);
            await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
              from_address: account.address,
              eventName: "EscapeCanceled",
            });
          });

          it("Should be possible to upgrade if a guardian escape is ongoing", async function () {
            const { account, accountContract, owner, guardian } = await deployFn();

            account.signer = owner;
            await accountContract.trigger_escape_guardian(12);

            account.signer = new LegacyArgentSigner(owner, guardian);
            await expectEvent(await upgradeAccount(account, argentAccountClassHash), {
              from_address: account.address,
              eventName: "EscapeCanceled",
            });
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
