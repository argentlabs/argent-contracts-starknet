import { expect } from "chai";
import { CallData } from "starknet";
import {
  LegacyMultisigKeyPair,
  SignerType,
  declareContract,
  declareFixtureContract,
  deployLegacyMultisig,
  expectEvent,
  provider,
  signerTypeToCustomEnum,
  upgradeAccount,
} from "../lib";
import { deployMultisig1_1 } from "../lib/multisig";

describe("ArgentMultisig: upgrade", function () {
  it("Upgrade from current version to FutureVersionMultisig", async function () {
    // This is the same as Argent Multisig but with a different version (to have another class hash)
    const argentMultisigFutureClassHash = await declareContract("MockFutureArgentMultisig");

    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, argentMultisigFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentMultisigFutureClassHash));
  });

  it("Upgrade from 0.1.0 to Current Version", async function () {
    const { account, signer } = await deployLegacyMultisig(await declareFixtureContract("ArgentMultisig-0.1.0"));
    const currentImpl = await declareContract("ArgentMultisigAccount");

    const tx = await upgradeAccount(account, currentImpl);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(currentImpl));

    const pubKey = (signer.keys[0] as LegacyMultisigKeyPair).publicKey.toString();
    await expectEvent(tx, {
      from_address: account.address,
      eventName: "SignerLinked",
      additionalKeys: [pubKey],
      data: CallData.compile([signerTypeToCustomEnum(SignerType.Starknet, { signer: pubKey })]),
    });
  });

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, "0x01").should.be.rejectedWith(
      `Class with hash ClassHash(\\n    StarkFelt(\\n        \\"0x0000000000000000000000000000000000000000000000000000000000000001\\",\\n    ),\\n) is not declared`,
    );

    const mockDappClassHash = await declareContract("MockDapp");
    await upgradeAccount(account, mockDappClassHash).should.be.rejectedWith(
      `EntryPointSelector(StarkFelt(\\"0x00fe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283\\")) not found in contract`,
    );
  });
});
