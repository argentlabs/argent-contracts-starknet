import { expect } from "chai";
import { CallData, uint256 } from "starknet";
import {
  LegacyMultisigKeyPair,
  MultisigSigner,
  SignerType,
  StarknetKeyPair,
  deployLegacyMultisig,
  expectEvent,
  manager,
  signerTypeToCustomEnum,
  sortByGuid,
  upgradeAccount,
} from "../lib";
import { deployMultisig, deployMultisig1_1 } from "../lib/multisig";

describe("ArgentMultisig: upgrade", function () {
  const artifactNames: any[] = [];

  before(async () => {
    const v010 = "0.1.0";
    const classHashV010 = await manager.declareArtifactMultisigContract(v010);
    artifactNames.push({
      name: v010,
      deployMultisig: (threshold: number) => deployLegacyMultisig(classHashV010, threshold),
    });
    const v011 = "0.1.1";
    const classHashV011 = await manager.declareArtifactMultisigContract(v011);
    artifactNames.push({
      name: v011,
      deployMultisig: (threshold: number) => deployLegacyMultisig(classHashV011, threshold),
    });
    const v020 = "0.2.0";
    const classHashV020 = await manager.declareArtifactMultisigContract(v020);
    artifactNames.push({
      name: v020,
      deployMultisig: (threshold: number) =>
        deployMultisig({ classHash: classHashV020, threshold, signersLength: threshold }),
    });
  });

  it("Upgrade from current version to FutureVersionMultisig", async function () {
    // This is the same as Argent Multisig but with a different version (to have another class hash)
    const argentMultisigFutureClassHash = await manager.declareLocalContract("MockFutureArgentMultisig");

    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, argentMultisigFutureClassHash);
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentMultisigFutureClassHash));
  });

  // TODO Filled with temp fix comparing to "0.2.0"
  it("Waiting for data to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const { name, deployMultisig } of artifactNames) {
        for (const threshold of [1, 3, 10]) {
          it(`Upgrade from ${name} to Current Version with ${threshold} key(s)`, async function () {
            const { account, accountContract, keys } = await deployMultisig(threshold);
            const currentImpl = await manager.declareLocalContract("ArgentMultisigAccount");

            const pubKeys =
              name == "0.2.0"
                ? keys.map((key: StarknetKeyPair) => key.guid)
                : keys.map((key: LegacyMultisigKeyPair) => key.publicKey);
            const accountSigners =
              name == "0.2.0" ? await accountContract.get_signer_guids() : await accountContract.get_signers();
            expect(accountSigners.length).to.equal(pubKeys.length);
            expect(pubKeys).to.have.members(accountSigners);

            const tx = await upgradeAccount(account, currentImpl);
            expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(currentImpl));
            if (name != "0.2.0") {
              for (const key of keys) {
                const snKeyPair = new StarknetKeyPair(key.privateKey);
                await expectEvent(tx, {
                  from_address: account.address,
                  eventName: "SignerLinked",
                  keys: [snKeyPair.guid.toString()],
                  data: CallData.compile([
                    signerTypeToCustomEnum(SignerType.Starknet, { signer: snKeyPair.publicKey }),
                  ]),
                });
              }
            }

            const ethContract = await manager.tokens.ethContract();
            const newSigners = sortByGuid(
              keys.map((key: LegacyMultisigKeyPair) => new StarknetKeyPair((key as LegacyMultisigKeyPair).privateKey)),
            );
            account.signer = new MultisigSigner(newSigners);

            const newAccountContract = await manager.loadContract(account.address);
            const getSignerGuids = await newAccountContract.get_signer_guids();
            expect(getSignerGuids.length).to.equal(newSigners.length);
            const newSignersGuids = newSigners.map(signer => signer.guid);
            expect(getSignerGuids).to.have.members(newSignersGuids);
            // Perform a transfer to make sure nothing is broken
            ethContract.connect(account);
            const recipient = "0xabde1";
            const amount = uint256.bnToUint256(1n);
            await manager.ensureSuccess(ethContract.transfer(recipient, amount, { maxFee: 5e14 }));
          });
        }
      }
    });
  });

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, "0x01").should.be.rejectedWith(
      "Class with hash 0x0000000000000000000000000000000000000000000000000000000000000001 is not declared.",
    );

    const mockDappClassHash = await manager.declareLocalContract("MockDapp");
    await upgradeAccount(account, mockDappClassHash).should.be.rejectedWith(
      "Entry point EntryPointSelector(0xfe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283) not found in contract.",
    );
  });
});
