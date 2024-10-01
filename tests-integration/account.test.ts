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
    const classHash = argentAccountClassHash;
    const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
    const udcCalls = deployer.buildUDCContractPayload({ classHash, salt, constructorCalldata, unique: false });
    const receipt = await manager.waitForTx(deployer.execute(udcCalls));

    // TODO: Add this back when we have implemented the event
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

  // TODO: Add this back once change_owner is implemented
  // describe("change_owner(new_owner, signature_r, signature_s)", function () {
  //   it("Should be possible to change_owner", async function () {
  //     const { accountContract, owner } = await deployAccount();
  //     const newOwner = randomStarknetKeyPair();
  //
  //     const chainId = await manager.getChainId();
  //     const starknetSignature = await signChangeOwnerMessage(accountContract.address, owner.guid, newOwner, chainId);
  //
  //     const receipt = await manager.waitForTx(accountContract.change_owner(starknetSignature));
  //
  //     await accountContract.get_owner_guid().should.eventually.equal(newOwner.guid);
  //
  //     const from_address = accountContract.address;
  //     await expectEvent(receipt, { from_address, eventName: "OwnerChanged", data: [newOwner.storedValue.toString()] });
  //     await expectEvent(receipt, { from_address, eventName: "OwnerChangedGuid", data: [newOwner.guid.toString()] });
  //   });
  //
  //   it("Expect 'argent/only-self' when called from another account", async function () {
  //     const { account } = await deployAccount();
  //     const { accountContract } = await deployAccount();
  //     accountContract.connect(account);
  //     await expectRevertWithErrorMessage(
  //       "argent/only-self",
  //       accountContract.change_owner(starknetSignatureType(12, 13, 14)),
  //     );
  //   });
  //
  //   it("Expect parsing error when new_owner is zero", async function () {
  //     const { accountContract } = await deployAccount();
  //     await expectRevertWithErrorMessage(
  //       "Failed to deserialize param #1",
  //       accountContract.change_owner(starknetSignatureType(0, 13, 14)),
  //     );
  //   });
  //
  //   it("Expect 'argent/invalid-owner-sig' when the signature to change owner is invalid", async function () {
  //     const { accountContract } = await deployAccount();
  //     await expectRevertWithErrorMessage(
  //       "argent/invalid-owner-sig",
  //       accountContract.change_owner(starknetSignatureType(12, 13, 14)),
  //     );
  //   });
  //
  //   it("Expect the escape to be reset", async function () {
  //     const { account, accountContract, owner, guardian } = await deployAccount();
  //
  //     const newOwner = randomStarknetKeyPair();
  //     account.signer = new ArgentSigner(guardian);
  //
  //     await accountContract.trigger_escape_owner(newOwner.compiledSigner);
  //     await hasOngoingEscape(accountContract).should.eventually.be.true;
  //     await manager.increaseTime(10);
  //
  //     account.signer = new ArgentSigner(owner, guardian);
  //     const chainId = await manager.getChainId();
  //     const starknetSignature = await signChangeOwnerMessage(accountContract.address, owner.guid, newOwner, chainId);
  //
  //     await accountContract.change_owner(starknetSignature);
  //
  //     await accountContract.get_owner_guid().should.eventually.equal(newOwner.guid);
  //     await hasOngoingEscape(accountContract).should.eventually.be.false;
  //   });
  // });

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
