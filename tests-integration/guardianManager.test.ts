import { expect } from "chai";
import { deployAccountWithoutGuardians, manager } from "../lib";

describe("Guardian Manager", function () {
  before(async () => {
    await manager.declareLocalContract("ArgentAccount");
  });

  describe("Get guardians info", function () {
    it("Empty if there is no guardian", async function () {
      const { accountContract } = await deployAccountWithoutGuardians();

      const guardiansInfo = await accountContract.get_guardians_info();

      expect(guardiansInfo).to.deep.equal([]);
    });
  });
});
