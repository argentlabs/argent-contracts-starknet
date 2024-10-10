import { expect } from "chai";
import { CallData } from "starknet";
import {
  ArgentSigner,
  deployAccountWithoutGuardian,
  expectRevertWithErrorMessage,
  manager,
  randomStarknetKeyPair,
} from "../lib";
describe("Owner Manager Tests", function () {
  before(async () => {
    await manager.declareLocalContract("ArgentAccount");
  });

  describe("Add Owners", function () {
    it("Add 1 Owner", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian();

      const newOwner = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner.signer] });
      await accountContract.add_owners(arrayOfSigner);
      const newOwners = await accountContract.get_owner_guids();

      expect(newOwners).to.deep.equal([owner.guid, newOwner.guid]);
    });

    it("Add 2 Owners", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian();

      const newOwner1 = randomStarknetKeyPair();
      const newOwner2 = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner1.signer, newOwner2.signer] });
      await accountContract.add_owners(arrayOfSigner);

      const newOwners = await accountContract.get_owner_guids();
      expect(newOwners).to.deep.equal([owner.guid, newOwner1.guid, newOwner2.guid]);
    });

    it("Add Owner Already in the List", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian();

      const arrayOfSigner = CallData.compile({ new_owners: [owner.signer] });
      await expectRevertWithErrorMessage("linked-set/already-in-set", accountContract.add_owners(arrayOfSigner));
    });
  });
  describe("Remove Owners Tests", function () {
    it("Remove 1 Owner", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian();
      const newOwner = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner.signer] });
      await accountContract.add_owners(arrayOfSigner);

      await accountContract.remove_owners([newOwner.guid]);
      const newOwnersAfterRemove = await accountContract.get_owner_guids();
      expect(newOwnersAfterRemove).to.deep.equal([owner.guid]);
    });
    it("Remove 2 Owners", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian();
      const newOwner1 = randomStarknetKeyPair();
      const newOwner2 = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner1.signer, newOwner2.signer] });
      await accountContract.add_owners(arrayOfSigner);

      await accountContract.remove_owners([newOwner1.guid, newOwner2.guid]);
      const newOwnersAfterRemove = await accountContract.get_owner_guids();
      expect(newOwnersAfterRemove).to.deep.equal([owner.guid]);
    });
    it("Remove Owner not in the List", async function () {
      const { accountContract } = await deployAccountWithoutGuardian();
      const newOwner = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner.signer] });
      await accountContract.add_owners(arrayOfSigner);
      await expectRevertWithErrorMessage("linked-set/item-not-found", accountContract.remove_owners([1n]));
    });
    it("Remove Owner /w 1 Owner", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardian();
      await expectRevertWithErrorMessage("argent/cant-remove-self", accountContract.remove_owners([owner.guid]));
    });
    it("Cant remove self even with multiple owners", async function () {
      const { accountContract, owner, account } = await deployAccountWithoutGuardian();
      const newOwner1 = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner1.signer] });
      await accountContract.add_owners(arrayOfSigner);
      account.signer = new ArgentSigner(owner, undefined);
      await expectRevertWithErrorMessage("argent/cant-remove-self", accountContract.remove_owners([owner.guid]));

      account.signer = new ArgentSigner(newOwner1, undefined);
      await accountContract.remove_owners([owner.guid]);
      const newOwnersAfterRemove = await accountContract.get_owner_guids();
      expect(newOwnersAfterRemove).to.deep.equal([newOwner1.guid]);
    });
  });
});
