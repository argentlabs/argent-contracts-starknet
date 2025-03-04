import { expect } from "chai";
import { CallData, hash, num } from "starknet";
import { StarknetKeyPair, deployContractUDC, manager, randomStarknetKeyPair } from "../lib";

describe("Deploy UDC", function () {
  let argentAccountClassHash: string;
  let guardian: StarknetKeyPair;
  let owner: StarknetKeyPair;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    guardian = randomStarknetKeyPair();
    owner = randomStarknetKeyPair();
  });

  it("Calculated contract address should match UDC", async function () {
    const callData = CallData.compile({
      owner: owner.signer,
      guardian: guardian.signerAsOption,
    });
    const salt = num.toHex(randomStarknetKeyPair().privateKey);
    const calculatedAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, callData, 0);
    const udcDeploymentAddress = await deployContractUDC(argentAccountClassHash, salt, callData);
    expect(calculatedAddress).to.equal(udcDeploymentAddress);

    // TODO: We should make sure event correctly triggered?
    
    // note about self deployment: As the address we get from self deployment
    // is calculated using calculateContractAddressFromHash
    // there is no need to test that the self deployment address is the
    // same as the when we deploy using the UDC
  });

  it("Shouldn't be possible to re-deploy the same contract using the same salt", async function () {
    const callData = CallData.compile({
      owner: owner.signer,
      guardian: guardian.signerAsOption,
    });
    const salt = num.toHex(randomStarknetKeyPair().privateKey);
    await deployContractUDC(argentAccountClassHash, salt, callData);
    await deployContractUDC(argentAccountClassHash, salt, callData).should.be.rejectedWith("Deployment failed: contract already deployed at address 0x");
  });
});
