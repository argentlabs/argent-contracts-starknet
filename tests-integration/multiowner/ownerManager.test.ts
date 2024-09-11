import { expect } from "chai";
import { CallData } from "starknet";
import {
  deployMoAccountWithoutGuardian,
  expectRevertWithErrorMessage,
  manager,
  randomStarknetKeyPair,
} from "../../lib";
describe("Owner Manager Tests", function () {
  let accountClassHash: string;

  before(async () => {
    accountClassHash = await manager.declareLocalContract("MultiOwnerAccount");
  });

  describe.only("Add Owners", function () {
    it("Add 1 Owner", async function () {
      const { accountContract, owner } = await deployMoAccountWithoutGuardian();

      const newOwner = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner.signer] });
      await accountContract.add_owners(arrayOfSigner);
      const newOwners = await accountContract.get_owner_guids();

      expect(newOwners).to.deep.equal([owner.guid, newOwner.guid]);
    });

    it("Add 2 Owners", async function () {
      const { accountContract, owner } = await deployMoAccountWithoutGuardian();

      const newOwner1 = randomStarknetKeyPair();
      const newOwner2 = randomStarknetKeyPair();
      const arrayOfSigner = CallData.compile({ new_owners: [newOwner1.signer, newOwner2.signer] });
      await accountContract.add_owners(arrayOfSigner);

      const newOwners = await accountContract.get_owner_guids();
      expect(newOwners).to.deep.equal([owner.guid, newOwner1.guid, newOwner2.guid]);
    });

    it("Add Owner Already in the List", async function () {
      const { accountContract, owner } = await deployMoAccountWithoutGuardian();

      const arrayOfSigner = CallData.compile({ new_owners: [owner.signer] });
      await expectRevertWithErrorMessage("linked-set/already-in-set", accountContract.add_owners(arrayOfSigner));
    });
  });
  describe("Remove Owners Tests", function () {
    it("Remove 1 Owner", async function () {
      const owner1 = randomStarknetKeyPair();
      const owner2 = randomStarknetKeyPair();
      const { accountContract, owners } = await deployMoAccountWithoutGuardian({ owners: [owner1, owner2] });
    });
  });
});
