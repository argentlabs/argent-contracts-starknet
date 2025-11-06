import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData, defaultDeployer, hash } from "starknet";
import {
  ArgentSigner,
  deployAccount,
  deployAccountWithoutGuardians,
  deployer,
  expectEvent,
  expectRevertWithErrorMessage,
  hasOngoingEscape,
  manager,
  randomStarknetKeyPair,
  signOwnerAliveMessage,
  zeroStarknetSignatureType,
} from "../../lib";

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
  });

  it("Deploy externally", async function () {
    const owner = randomStarknetKeyPair();
    const guardian = randomStarknetKeyPair();
    const constructorCalldata = CallData.compile({ owner: owner.signer, guardian: guardian.signerAsOption });

    const salt = "123";
    const contractAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, constructorCalldata, 0);
    const udcCalls = defaultDeployer.buildDeployerCall(
      {
        classHash: argentAccountClassHash,
        salt,
        constructorCalldata,
        unique: false,
      },
      contractAddress,
    );
    const receipt = await manager.waitForTx(deployer.execute(udcCalls.calls));
    await expectEvent(receipt, {
      from_address: contractAddress,
      eventName: "AccountCreated",
      keys: [owner.storedValue.toString()],
      data: [guardian.storedValue.toString()],
    });
    await expectEvent(receipt, {
      from_address: contractAddress,
      eventName: "AccountCreatedGuid",
      keys: [owner.guid.toString()],
      data: [guardian.guid.toString()],
    });

    const accountContract = await manager.loadContract(contractAddress);
    await accountContract.get_owners_guids().should.eventually.deep.equal([owner.guid]);
    await accountContract.is_owner_guid(owner.guid).should.eventually.equal(true);

    expect((await accountContract.get_guardian_guid()).unwrap()).to.equal(guardian.guid);
    await accountContract.get_guardians_guids().should.eventually.deep.equal([guardian.guid]);
  });

  it(`Self deployment`, async function () {
    const { accountContract, owner } = await deployAccountWithoutGuardians({ selfDeploy: true });

    await accountContract.get_owners_guids().should.eventually.deep.equal([owner.guid]);
    await accountContract.get_guardians_guids().should.eventually.deep.equal([]);
  });

  it("Expect an error when owner is zero", async function () {
    const guardian = new CairoOption(CairoOptionVariant.None);
    await expectRevertWithErrorMessage(
      "Failed to deserialize param #1",
      deployer.deployContract({
        classHash: argentAccountClassHash,
        constructorCalldata: CallData.compile({ owner: zeroStarknetSignatureType(), guardian }),
      }),
    );
  });

  describe("change_owners(...)", function () {
    it("Should be possible to change_owners", async function () {
      const { accountContract, owner } = await deployAccount();
      const newOwner = randomStarknetKeyPair();

      const chainId = await manager.getChainId();
      const currentTimestamp = await manager.getCurrentTimestamp();
      const signerAliveSignature = await signOwnerAliveMessage(
        accountContract.address,
        newOwner,
        chainId,
        currentTimestamp + 1000,
      );
      const calldata = CallData.compile([
        ...CallData.compile({ owner_guids_to_remove: [owner.guid], owners_to_add: [newOwner.signer] }),
        0,
        ...signerAliveSignature,
      ]);
      // Can't just do account.change_owners(x, y) because parsing goes wrong...
      await manager.ensureSuccess(await accountContract.invoke("change_owners", calldata));
      await accountContract.get_owners_guids().should.eventually.deep.equal([newOwner.guid]);
    });

    it("Should not require a signature if owner is still valid", async function () {
      const { accountContract, owners } = await deployAccount({
        owners: Array.from({ length: 2 }, () => randomStarknetKeyPair()),
      });
      const [owner, newOwner] = owners;

      const calldata = CallData.compile({
        owner_guids_to_remove: [newOwner.guid],
        owners_to_add: [],
        owner_alive_signature: new CairoOption(CairoOptionVariant.None),
      });
      // Can't just do account.change_owners(x, y) because parsing goes wrong...
      await manager.ensureSuccess(await accountContract.invoke("change_owners", calldata));
      await accountContract.get_owners_guids().should.eventually.deep.equal([owner.guid]);
    });

    it("Expect parsing error when new_owner is zero", async function () {
      const { accountContract } = await deployAccount();
      const calldata = CallData.compile([
        ...CallData.compile({ owner_guids_to_remove: [] }),
        1,
        ...CallData.compile({ signer: zeroStarknetSignatureType() }), // malformed signer
        1, // no alive signature
      ]);
      await expectRevertWithErrorMessage(
        "Failed to deserialize param #2",
        accountContract.invoke("change_owners", calldata),
      );
    });
  });

  describe("change_guardians()", function () {
    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      const newOwner = randomStarknetKeyPair();

      await accountContract.trigger_escape_owner(newOwner.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await manager.increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      const calldata = CallData.compile([{ guardian_guids_to_remove: [guardian.guid], guardians_to_add: [] }]);
      await accountContract.invoke("change_guardians", calldata);

      expect((await accountContract.get_guardian_guid()).isNone()).to.be.true;

      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  it("Expect 'Entry point X not found' when calling the constructor", async function () {
    const { account } = await deployAccount();
    await manager
      .waitForTx(
        account.execute({
          contractAddress: account.address,
          entrypoint: "constructor",
          calldata: CallData.compile({ owner: 12, guardian: 13 }),
        }),
      )
      .should.be.rejectedWith(
        "(0x617267656e742f6d756c746963616c6c2d6661696c6564 ('argent/multicall-failed'), 0x0 (''), 0x454e545259504f494e545f4e4f545f464f554e44 ('ENTRYPOINT_NOT_FOUND'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED'))",
      );
  });
});
