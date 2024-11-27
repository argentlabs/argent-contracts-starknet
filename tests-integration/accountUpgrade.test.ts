import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData } from "starknet";
import {
  ArgentSigner,
  ContractWithClass,
  LegacyWebauthnOwner,
  StarknetKeyPair,
  WebauthnOwner,
  deployAccount,
  deployAccountWithoutGuardian,
  deployLegacyAccount,
  deployLegacyAccountWithoutGuardian,
  deployOldAccountWithProxy,
  deployOldAccountWithProxyWithoutGuardian,
  expectEvent,
  expectRevertWithErrorMessage,
  getUpgradeDataLegacy,
  manager,
  randomEip191KeyPair,
  randomEthKeyPair,
  randomSecp256r1KeyPair,
  randomStarknetKeyPair,
  randomWebauthnLegacyCairo0Owner,
  randomWebauthnLegacyOwner,
  upgradeAccount,
} from "../lib";

describe("ArgentAccount: upgrade", function () {
  let argentAccountClassHash: string;
  let mockDapp: ContractWithClass;
  let classHashV040: string;
  const upgradeData: any[] = [];

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDapp = await manager.deployContract("MockDapp");

    upgradeData.push({
      name: "Legacy",
      deployAccount: async () => await deployOldAccountWithProxy(),
      extraCalldata: ["0"],
      deployAccountWithoutGuardian: async () => await deployOldAccountWithProxyWithoutGuardian(),
      // Gotta call like that as the entrypoint is not found on the contract for legacy versions
      triggerEscapeOwner: { entrypoint: "triggerEscapeSigner" },
      triggerEscapeGuardian: { entrypoint: "triggerEscapeGuardian" },
    });

    const v030 = "0.3.0";
    const classHashV030 = await manager.declareArtifactAccountContract(v030);
    const triggerEscapeOwnerV03 = { entrypoint: "trigger_escape_owner", calldata: [12] };
    const triggerEscapeGuardianV03 = { entrypoint: "trigger_escape_guardian", calldata: [12] };
    upgradeData.push({
      name: v030,
      deployAccount: async () => deployLegacyAccount(classHashV030),
      deployAccountWithoutGuardian: async () => deployLegacyAccountWithoutGuardian(classHashV030),
      triggerEscapeOwner: triggerEscapeOwnerV03,
      triggerEscapeGuardian: triggerEscapeGuardianV03,
    });

    const v031 = "0.3.1";
    const classHashV031 = await manager.declareArtifactAccountContract(v031);
    upgradeData.push({
      name: v031,
      deployAccount: async () => deployLegacyAccount(classHashV031),
      deployAccountWithoutGuardian: async () => deployLegacyAccountWithoutGuardian(classHashV031),
      triggerEscapeOwner: triggerEscapeOwnerV03,
      triggerEscapeGuardian: triggerEscapeGuardianV03,
    });

    const v040 = "0.4.0";
    classHashV040 = await manager.declareArtifactAccountContract(v040);
    const triggerEscapeOwnerV04 = {
      entrypoint: "trigger_escape_owner",
      calldata: CallData.compile(randomStarknetKeyPair().compiledSigner),
    };
    const triggerEscapeGuardianV04 = {
      entrypoint: "trigger_escape_guardian",
      calldata: CallData.compile([new CairoOption(CairoOptionVariant.None)]),
    };
    upgradeData.push({
      name: v040,
      deployAccount: async () => deployAccount({ classHash: classHashV040 }),
      deployAccountWithoutGuardian: async () => deployAccountWithoutGuardian({ classHash: classHashV040 }),
      triggerEscapeOwner: triggerEscapeOwnerV04,
      triggerEscapeGuardian: triggerEscapeGuardianV04,
    });
  });

  it("Waiting for upgradeData to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const {
        name,
        deployAccount,
        triggerEscapeOwner,
        triggerEscapeGuardian,
        deployAccountWithoutGuardian,
        extraCalldata,
      } of upgradeData) {
        it(`[${name}] Should be possible to upgrade `, async function () {
          const { account } = await deployAccount();
          await upgradeAccount(account, argentAccountClassHash, extraCalldata);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          mockDapp.connect(account);
          // This should work as long as we support the "old" signature format [r1, s1, r2, s2]
          account.cairoVersion = "1";
          await manager.ensureSuccess(mockDapp.set_number(42));
        });

        it(`[${name}] Should be possible to upgrade without guardian from ${name}`, async function () {
          const { account } = await deployAccountWithoutGuardian();
          await upgradeAccount(account, argentAccountClassHash, extraCalldata);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          account.cairoVersion = "1";
          await manager.ensureSuccess(mockDapp.set_number(42));
        });

        it(`[${name}] Upgrade cairo with multicall`, async function () {
          const random = randomStarknetKeyPair().publicKey;
          const { account } = await deployAccount();
          const upgradeData = account.cairoVersion
            ? CallData.compile([[mockDapp.populateTransaction.set_number(random)]])
            : getUpgradeDataLegacy([mockDapp.populateTransaction.set_number(random)]);
          await upgradeAccount(account, argentAccountClassHash, upgradeData);
          expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));
          await mockDapp.get_number(account.address).should.eventually.equal(random);
          // We don't really care about the value here, just that it is successful
          await manager.ensureSuccess(mockDapp.set_number(random));
        });

        it(`[${name}] Should be possible to upgrade if an owner escape is ongoing`, async function () {
          const { account, guardian } = await deployAccount();

          const oldSigner = account.signer;

          if (guardian instanceof StarknetKeyPair) {
            account.signer = new ArgentSigner(guardian);
          } else {
            account.signer = guardian;
          }

          await manager.ensureSuccess(
            account.execute({
              contractAddress: account.address,
              ...triggerEscapeOwner,
            }),
          );

          account.signer = oldSigner;
          await expectEvent(await upgradeAccount(account, argentAccountClassHash, extraCalldata), {
            from_address: account.address,
            eventName: "EscapeCanceled",
          });
        });

        it(`[${name}] Should be possible to upgrade if a guardian escape is ongoing`, async function () {
          const { account, owner } = await deployAccount();

          const oldSigner = account.signer;

          if (owner instanceof StarknetKeyPair) {
            account.signer = new ArgentSigner(owner);
          } else {
            account.signer = owner;
          }

          await manager.ensureSuccess(
            account.execute({
              contractAddress: account.address,
              ...triggerEscapeGuardian,
            }),
          );

          account.signer = oldSigner;
          await expectEvent(await upgradeAccount(account, argentAccountClassHash, extraCalldata), {
            from_address: account.address,
            eventName: "EscapeCanceled",
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

  describe("Testing upgrade version 0.4.0 with every signer type", function () {
    const nonStarknetKeyPairs = [
      { name: "Ethereum signature", keyPair: randomEthKeyPair },
      { name: "Secp256r1 signature", keyPair: randomSecp256r1KeyPair },
      { name: "Eip191 signature", keyPair: randomEip191KeyPair },
      { name: "Webauthn signature", keyPair: randomWebauthnLegacyOwner },
      { name: "Webauthn signature (cairo0)", keyPair: randomWebauthnLegacyCairo0Owner },
    ];

    before(async () => {
      await manager.declareFixtureContract("Sha256Cairo0");
    });

    for (const { name, keyPair } of nonStarknetKeyPairs) {
      it(`[${name}] Testing upgrade`, async function () {
        const owner = keyPair();
        const { account, guardian } = await deployAccount({ owner, classHash: classHashV040 });

        await upgradeAccount(account, argentAccountClassHash);
        expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

        mockDapp.connect(account);
        // We have to update the owner with the new webauthn format
        if (owner instanceof LegacyWebauthnOwner) {
          account.signer = new ArgentSigner(new WebauthnOwner(owner.getPrivateKey()), guardian);
        }
        await manager.ensureSuccess(mockDapp.set_number(42));
      });

      it(`[${name}] Testing upgrade without guardian ${name}`, async function () {
        const owner = keyPair();
        const { account } = await deployAccountWithoutGuardian({ owner, classHash: classHashV040 });

        await upgradeAccount(account, argentAccountClassHash);
        expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentAccountClassHash));

        mockDapp.connect(account);
        // We have to update the owner with the new webauthn format
        if (owner instanceof LegacyWebauthnOwner) {
          account.signer = new ArgentSigner(new WebauthnOwner(owner.getPrivateKey()));
        }
        await manager.ensureSuccess(mockDapp.set_number(42));
      });
    }
  });
});
