import { declareContract, deployContractUDC, calculateContractAddress, randomKeyPair } from "./lib";
import { num } from "starknet";

const salt = num.toHex(randomKeyPair().privateKey);
const owner = randomKeyPair();
const guardian = randomKeyPair();

describe("ArgentAccount", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Deploy current version", async function () {
    const calculatedAddress = await calculateContractAddress(
      argentAccountClassHash,
      salt,
      owner.publicKey,
      guardian.publicKey,
    );
    const udcDeploymentAddress = await deployContractUDC(
      argentAccountClassHash,
      salt,
      owner.publicKey,
      guardian.publicKey,
    );

    calculatedAddress.should.equal(udcDeploymentAddress);
  });
});
