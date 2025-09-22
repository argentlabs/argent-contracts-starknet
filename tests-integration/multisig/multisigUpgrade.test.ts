import { expect } from "chai";
import { Account, CallData, Contract, RPC, uint256 } from "starknet";
import {
  ContractWithClass,
  KeyPair,
  LegacyMultisigKeyPair,
  MultisigSigner,
  SignerType,
  StarknetKeyPair,
  deployLegacyMultisig,
  deployMultisig,
  deployMultisig1_1,
  expectEvent,
  fundAccount,
  generateRandomNumber,
  manager,
  signerTypeToCustomEnum,
  sortByGuid,
  upgradeAccount,
} from "../../lib";

interface DeployMultisigReturn {
  account: Account;
  accountContract: Contract;
  keys: KeyPair[] | LegacyMultisigKeyPair[];
}

interface UpgradeDataEntry {
  name: string;
  deployMultisig: (threshold: number) => Promise<DeployMultisigReturn>;
  getGuidsSelector: string;
}

describe("ArgentMultisig: upgrade", function () {
  const artifactNames: UpgradeDataEntry[] = [];
  let mockDapp: ContractWithClass;

  before(async () => {
    const v010 = "0.1.0";
    const classHashV010 = await manager.declareArtifactMultisigContract(v010);
    artifactNames.push({
      name: v010,
      // Doesn't support V3 transactions
      deployMultisig: (threshold: number) => deployLegacyMultisig(classHashV010, threshold, RPC.ETransactionVersion.V2),
      getGuidsSelector: "get_signers",
    });
    // Start of support for V3 transactions
    const v011 = "0.1.1";
    const classHashV011 = await manager.declareArtifactMultisigContract(v011);
    artifactNames.push({
      name: v011,
      deployMultisig: (threshold: number) => deployLegacyMultisig(classHashV011, threshold),
      getGuidsSelector: "get_signers",
    });
    const v020 = "0.2.0";
    const classHashV020 = await manager.declareArtifactMultisigContract(v020);
    artifactNames.push({
      name: v020,
      deployMultisig: (threshold: number) =>
        deployMultisig({ classHash: classHashV020, threshold, signersLength: threshold }),
      getGuidsSelector: "get_signer_guids",
    });
    mockDapp = await manager.declareAndDeployContract("MockDapp");
  });

  it("Upgrade from current version to FutureVersionMultisig", async function () {
    // This is the same as Argent Multisig but with a different version (to have another class hash)
    const argentMultisigFutureClassHash = await manager.declareLocalContract("MockFutureArgentMultisig");

    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, argentMultisigFutureClassHash);
    expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(argentMultisigFutureClassHash));
    const strkContract = await manager.tokens.strkContract();
    strkContract.connect(account);
    const recipient = "0xabde1";
    const amount = uint256.bnToUint256(1n);
    await manager.ensureSuccess(strkContract.transfer(recipient, amount));
  });

  it("Shouldn't be possible to upgrade from current version to FutureVersionMultisig with extra calldata", async function () {
    const argentMultisigFutureClassHash = await manager.declareLocalContract("MockFutureArgentMultisig");

    const { account } = await deployMultisig1_1();
    await upgradeAccount(account, argentMultisigFutureClassHash, [1]).should.be.rejectedWith("argent/unexpected-data");
  });

  it("Waiting for data to be filled", function () {
    describe("Upgrade to latest version", function () {
      for (const { name, deployMultisig, getGuidsSelector } of artifactNames) {
        for (const threshold of [1, 3, 10]) {
          it(`Upgrade from ${name} to Current Version with ${threshold} key(s)`, async function () {
            const { account, accountContract, keys } = await deployMultisig(threshold);
            const currentImpl = await manager.declareLocalContract("ArgentMultisigAccount");

            const pubKeys = keys.map((key) => key.guid);
            const accountSigners = (await accountContract.call(getGuidsSelector)) as bigint[];
            expect(accountSigners.length).to.equal(pubKeys.length);
            expect(pubKeys).to.have.members(accountSigners);

            const tx = await upgradeAccount(account, currentImpl);
            expect(BigInt(await manager.getClassHashAt(account.address))).to.equal(BigInt(currentImpl));
            // SignerLinked event is not emitted when upgrading from 0.2.0
            if (name != "0.2.0") {
              for (const key of keys) {
                const snKeyPair = new StarknetKeyPair((key as any).privateKey);
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

            const newSigners = sortByGuid(keys.map((key: any) => new StarknetKeyPair(key.privateKey)));

            const newAccountContract = await manager.loadContract(account.address);
            const getSignerGuids = await newAccountContract.get_signer_guids();
            expect(getSignerGuids.length).to.equal(newSigners.length);
            const newSignersGuids = newSigners.map((signer) => signer.guid);
            expect(getSignerGuids).to.have.members(newSignersGuids);

            // As old version might be in V1 or V2, we need to create a new account with V3
            const accountV3 = new Account(
              account,
              account.address,
              new MultisigSigner(newSigners),
              "1",
              RPC.ETransactionVersion.V3,
            );
            // Need some STRK for v3 transactions
            await fundAccount(accountV3.address, 1e18, "STRK");

            // Default estimation is too low, we need to increase it
            mockDapp.connect(accountV3);
            const randomNumber = generateRandomNumber();
            const estimate = await mockDapp.estimateFee.set_number(randomNumber);
            estimate.resourceBounds.l1_gas.max_amount = estimate.resourceBounds.l1_gas.max_amount * 4;
            // Perform a simple dapp interaction to make sure nothing is broken
            await manager.ensureSuccess(
              accountV3.execute(mockDapp.populateTransaction.set_number(randomNumber), estimate),
            );
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
      "(0x617267656e742f6d756c746963616c6c2d6661696c6564 ('argent/multicall-failed'), 0x0 (''), 0x454e545259504f494e545f4e4f545f464f554e44 ('ENTRYPOINT_NOT_FOUND'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED')).",
    );
  });
});
