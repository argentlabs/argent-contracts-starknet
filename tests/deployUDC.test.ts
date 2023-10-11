import { declareContract, deployContractUDC, randomKeyPair } from "./lib";
import { num, hash } from "starknet";

const salt = num.toHex(randomKeyPair().privateKey);
const owner = randomKeyPair();
const guardian = randomKeyPair();

describe("Deploy UDC", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Calculated contract address should match UDC", async function () {
    let callData = {
      signer: owner.publicKey,
      guardian: guardian.publicKey,
    };
    const calculatedAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, callData, 0);
    const udcDeploymentAddress = await deployContractUDC(
      argentAccountClassHash,
      salt,
      owner.publicKey,
      guardian.publicKey,
    );

    calculatedAddress.should.equal(udcDeploymentAddress);
  });
});
