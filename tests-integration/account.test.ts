import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData, hash } from "starknet";
import {
  ArgentSigner,
  deployAccount,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployer,
  expectRevertWithErrorMessage,
  hasOngoingEscape,
  manager,
  randomStarknetKeyPair,
  signChangeOwnerMessage,
  starknetSignatureType,
  zeroStarknetSignatureType,
} from "../lib";

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
    const udcCalls = deployer.buildUDCContractPayload({
      classHash: argentAccountClassHash,
      salt,
      constructorCalldata,
      unique: false,
    });
    const receipt = await manager.waitForTx(deployer.execute(udcCalls));

    // TODO: Add this back once the event is implemented
    // await expectEvent(receipt, {
    //   from_address: contractAddress,
    //   eventName: "AccountCreated",
    //   keys: [owner.storedValue.toString()],
    //   data: [guardian.storedValue.toString()],
    // });

    // await expectEvent(receipt, {
    //   from_address: contractAddress,
    //   eventName: "AccountCreatedGuid",
    //   keys: [owner.guid.toString()],
    //   data: [guardian.guid.toString()],
    // });

    const accountContract = await manager.loadContract(contractAddress);
    await accountContract.get_owner_guid().should.eventually.equal(owner.guid);
    await accountContract.is_owner_guid(owner.guid).should.eventually.equal(true);

    expect((await accountContract.get_guardian_guid()).unwrap()).to.equal(guardian.guid);
    await accountContract.get_guardian_backup().should.eventually.equal(0n);
  });

  for (const useTxV3 of [false, true]) {
    it(`Self deployment (TxV3: ${useTxV3})`, async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian({ useTxV3, selfDeploy: true });

      await accountContract.get_owner_guid().should.eventually.equal(owner.guid);
      await accountContract.get_guardian().should.eventually.equal(0n);
      await accountContract.get_guardian_backup().should.eventually.equal(0n);
    });
  }

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

  describe("replace_all_owners_with_one(...)", function () {
    it("Should be possible to replace_all_owners_with_one", async function () {
      const { accountContract } = await deployAccount();
      const newOwner = randomStarknetKeyPair();

      const chainId = await manager.getChainId();
      const latestBlockTimestamp = await manager.getCurrentTimestamp();
      const futureTimestamp = latestBlockTimestamp + 1000;
      const starknetSignature = await signChangeOwnerMessage(
        accountContract.address,
        newOwner,
        chainId,
        futureTimestamp,
      );
      // Wtf??? For some reason I have to push to array instead of passing as last arg??? There is def a bug here
      starknetSignature.push(`0x${futureTimestamp.toString(16)}`);
      const receipt = await manager.waitForTx(await accountContract.replace_all_owners_with_one(starknetSignature));
      await accountContract.get_owner_guid().should.eventually.equal(newOwner.guid);
      // TODO bring this back
      // const from_address = accountContract.address;
      // await expectEvent(receipt, { from_address, eventName: "OwnerChanged", data: [newOwner.storedValue.toString()] });
      // await expectEvent(receipt, { from_address, eventName: "OwnerChangedGuid", data: [newOwner.guid.toString()] });
    });

    it("Expect parsing error when new_owner is zero", async function () {
      const { accountContract } = await deployAccount();
      await expectRevertWithErrorMessage(
        "Failed to deserialize param #1",
        accountContract.replace_all_owners_with_one(starknetSignatureType(0, 13, 14), 1),
      );
    });
  });

  describe("change_guardian(new_guardian)", function () {
    it("Shouldn't be possible to use a guardian with pubkey = 0", async function () {
      const { account } = await deployAccount();
      const { accountContract } = await deployAccount();
      accountContract.connect(account);
      await expectRevertWithErrorMessage(
        "Failed to deserialize param #1",
        accountContract.change_guardian(CallData.compile([zeroStarknetSignatureType()])),
      );
    });

    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);

      const newOwner = randomStarknetKeyPair();
      const newGuardian = randomStarknetKeyPair();

      await accountContract.trigger_escape_owner(newOwner.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await manager.increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.change_guardian(newGuardian.compiledSignerAsOption);

      expect((await accountContract.get_guardian_guid()).unwrap()).to.equal(newGuardian.guid);

      await hasOngoingEscape(accountContract).should.eventually.be.false;
    });
  });

  describe("change_guardian_backup(new_guardian)", function () {
    it("Expect the escape to be reset", async function () {
      const { account, accountContract, owner, guardian } = await deployAccountWithGuardianBackup();

      const newOwner = randomStarknetKeyPair();
      account.signer = new ArgentSigner(guardian);
      const newGuardian = randomStarknetKeyPair();

      await accountContract.trigger_escape_owner(newOwner.compiledSigner);
      await hasOngoingEscape(accountContract).should.eventually.be.true;
      await manager.increaseTime(10);

      account.signer = new ArgentSigner(owner, guardian);
      await accountContract.change_guardian_backup(newGuardian.compiledSignerAsOption);

      expect((await accountContract.get_guardian_backup_guid()).unwrap()).to.equal(newGuardian.guid);
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
        "Entry point EntryPointSelector(0x28ffe4ff0f226a9107253e17a904099aa4f63a02a5621de0576e5aa71bc5194) not found in contract.",
      );
  });
});
