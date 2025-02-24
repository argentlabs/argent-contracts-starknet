import { expect } from "chai";
import { CairoOption, CairoOptionVariant, CallData } from "starknet";
import { deployAccountWithoutGuardians, expectRevertWithErrorMessage, manager, randomStarknetKeyPair } from "../lib";
describe("Owner Manager Tests", function () {
  before(async () => {
    await manager.declareLocalContract("ArgentAccount");
  });

  describe("Add Owners", function () {
    it("Add 1 Owner", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardians();

      const newOwner = randomStarknetKeyPair();
      await accountContract.change_owners(
        CallData.compile({
          remove: [],
          add: [newOwner.signer],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );
      const newOwners = await accountContract.get_owners_guids();

      expect(newOwners).to.deep.equal([owner.guid, newOwner.guid]);
    });

    it("Add 2 Owners", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardians();

      const newOwner1 = randomStarknetKeyPair();
      const newOwner2 = randomStarknetKeyPair();

      await accountContract.change_owners(
        CallData.compile({
          remove: [],
          add: [newOwner1.signer, newOwner2.signer],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );

      const newOwners = await accountContract.get_owners_guids();
      expect(newOwners).to.deep.equal([owner.guid, newOwner1.guid, newOwner2.guid]);
    });

    it("Add Owner Already in the List", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardians();

      await expectRevertWithErrorMessage(
        "linked-set/already-in-set",
        accountContract.change_owners(
          CallData.compile({
            remove: [],
            add: [owner.signer],
            alive_signature: new CairoOption(CairoOptionVariant.None),
          }),
        ),
      );
    });
  });
  describe("Remove Owners Tests", function () {
    it("Remove 1 Owner", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardians();
      const newOwner = randomStarknetKeyPair();
      await accountContract.change_owners(
        CallData.compile({
          remove: [],
          add: [newOwner.signer],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );

      await accountContract.change_owners(
        CallData.compile({
          remove: [newOwner.guid],
          add: [],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );
      const newOwnersAfterRemove = await accountContract.get_owners_guids();
      expect(newOwnersAfterRemove).to.deep.equal([owner.guid]);
    });
    it("Remove 2 Owners", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardians();
      const newOwner1 = randomStarknetKeyPair();
      const newOwner2 = randomStarknetKeyPair();
      await accountContract.change_owners(
        CallData.compile({
          remove: [],
          add: [newOwner1.signer, newOwner2.signer],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );

      await accountContract.change_owners(
        CallData.compile({
          remove: [newOwner1.guid, newOwner2.guid],
          add: [],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );
      const newOwnersAfterRemove = await accountContract.get_owners_guids();
      expect(newOwnersAfterRemove).to.deep.equal([owner.guid]);
    });
    it("Remove Owner not in the List", async function () {
      const { accountContract } = await deployAccountWithoutGuardians();
      const newOwner = randomStarknetKeyPair();
      await accountContract.change_owners(
        CallData.compile({
          remove: [],
          add: [newOwner.signer],
          alive_signature: new CairoOption(CairoOptionVariant.None),
        }),
      );
      await expectRevertWithErrorMessage(
        "linked-set/item-not-found",
        accountContract.change_owners(
          CallData.compile({
            remove: [1n],
            add: [],
            alive_signature: new CairoOption(CairoOptionVariant.None),
          }),
        ),
      );
    });
    it("Can't self remove without signature", async function () {
      const { accountContract, owner } = await deployAccountWithoutGuardians();
      await expectRevertWithErrorMessage(
        "argent/missing-owner-alive",
        accountContract.change_owners(
          CallData.compile({
            remove: [owner.guid],
            add: [],
            alive_signature: new CairoOption(CairoOptionVariant.None),
          }),
        ),
      );
    });
  });
});
