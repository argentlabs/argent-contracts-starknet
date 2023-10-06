import { declareContract, deployContractUDC, calculateContractAddress, randomKeyPair } from "./lib";
import { num } from "starknet";

const salt = num.toHex(randomKeyPair().privateKey);
const owner = randomKeyPair();
const guardian = randomKeyPair();

describe("Deploy UDC", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Calculated contract address should match UDC", async function () {
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
