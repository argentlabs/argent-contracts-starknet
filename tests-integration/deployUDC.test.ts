import { expect } from "chai";
import { declareContract, deployContractUdc, randomKeyPair } from "./lib";
import { num, hash } from "starknet";

const salt = num.toHex(randomKeyPair().privateKey);
const owner = randomKeyPair();
const guardian = randomKeyPair();

describe("Deploy UDC", function () {
  it("Calculated contract address should match UDC", async function () {
    const argentAccountClassHash = await declareContract("ArgentAccount");

    const callData = {
      signer: owner.publicKey,
      guardian: guardian.publicKey,
    };
    const calculatedAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, callData, 0);
    const udcDeploymentAddress = await deployContractUdc(
      argentAccountClassHash,
      salt,
      owner.publicKey,
      guardian.publicKey,
    );

    expect(calculatedAddress).to.equal(udcDeploymentAddress);

    // note about self deployment: As the address we get from self deployment
    // is calculated using calculateContractAddressFromHash
    // there is no need to test that the self deployment address is the
    // same as the when we deploy using the UDC
  });
});
