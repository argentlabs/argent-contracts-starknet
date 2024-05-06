import { expect } from "chai";
import { CallData, uint256 } from "starknet";
import {
  LegacyMultisigKeyPair,
  MultisigSigner,
  SignerType,
  StarknetKeyPair,
  deployLegacyMultisig,
  ensureSuccess,
  expectEvent,
  provider,
  signerTypeToCustomEnum,
  sortByGuid,
  upgradeAccount,
  waitForTransaction,
} from "../lib";
import { deployMultisig1_1 } from "../lib/multisig";

describe("ArgentMultisig: upgrade", function () {
  it("Upgrade from current version to FutureVersionMultisig", async function () {
    // This is the same as Argent Multisig but with a different version (to have another class hash)
    const argentMultisigFutureClassHash = await provider.declareLocalContract("MockFutureArgentMultisig");

    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, argentMultisigFutureClassHash);
    expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(argentMultisigFutureClassHash));
  });

  for (const threshold of [1, 3, 10]) {
    it(`Upgrade from 0.1.0 to Current Version with ${threshold} key(s)`, async function () {
      const { account, accountContract, signers } = await deployLegacyMultisig(
        await provider.declareFixtureContract("ArgentMultisig-0.1.0"),
        threshold,
      );
      const currentImpl = await provider.declareLocalContract("ArgentMultisigAccount");

      const pubKeys = signers.keys.map((key) => (key as LegacyMultisigKeyPair).publicKey);
      const accountSigners = await accountContract.get_signers();
      expect(accountSigners.length).to.equal(pubKeys.length);
      expect(pubKeys).to.have.members(accountSigners);

      const tx = await upgradeAccount(account, currentImpl);
      expect(BigInt(await provider.getClassHashAt(account.address))).to.equal(BigInt(currentImpl));

      for (const key of signers.keys) {
        const snKeyPair = new StarknetKeyPair((key as LegacyMultisigKeyPair).privateKey);
        await expectEvent(tx, {
          from_address: account.address,
          eventName: "SignerLinked",
          additionalKeys: [snKeyPair.guid.toString()],
          data: CallData.compile([signerTypeToCustomEnum(SignerType.Starknet, { signer: snKeyPair.publicKey })]),
        });
      }

      const ethContract = await provider.tokens.ethContract();
      const newSigners = sortByGuid(
        signers.keys.map((key) => new StarknetKeyPair((key as LegacyMultisigKeyPair).privateKey)),
      );
      account.signer = new MultisigSigner(newSigners);

      const newAccountContract = await provider.loadContract(account.address);
      const getSignerGuids = await newAccountContract.get_signer_guids();
      expect(getSignerGuids.length).to.equal(newSigners.length);
      const newSignersGuids = newSigners.map((signer) => signer.guid);
      expect(getSignerGuids).to.have.members(newSignersGuids);
      // Perform a transfer to make sure nothing is broken
      ethContract.connect(account);
      const recipient = "0xabde1";
      const amount = uint256.bnToUint256(1n);
      const transfer = await ethContract.transfer(recipient, amount, { maxFee: 5e14 });
      await ensureSuccess(await waitForTransaction(transfer));
    });
  }

  it("Reject invalid upgrade targets", async function () {
    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, "0x01").should.be.rejectedWith(
      `Class with hash ClassHash(\\n    StarkFelt(\\n        \\"0x0000000000000000000000000000000000000000000000000000000000000001\\",\\n    ),\\n) is not declared`,
    );

    const mockDappClassHash = await provider.declareLocalContract("MockDapp");
    await upgradeAccount(account, mockDappClassHash).should.be.rejectedWith(
      `EntryPointSelector(StarkFelt(\\"0x00fe80f537b66d12a00b6d3c072b44afbb716e78dde5c3f0ef116ee93d3e3283\\")) not found in contract`,
    );
  });
});
