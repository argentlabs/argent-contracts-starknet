import { expect } from "chai";
import { CallData, defaultDeployer, hash, num } from "starknet";
import { StarknetKeyPair, deployContractUDC, deployer, expectEvent, manager, randomStarknetKeyPair } from "../lib";

describe("Deploy UDC", function () {
  let argentAccountClassHash: string;
  let owner: StarknetKeyPair;
  let guardian: StarknetKeyPair;

  before(async () => {
    argentAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    owner = randomStarknetKeyPair();
    guardian = randomStarknetKeyPair();
  });

  it("Calculated contract address should match UDC", async function () {
    const callData = CallData.compile({
      owner: owner.signer,
      guardian: guardian.signerAsOption,
    });
    const salt = num.toHex(randomStarknetKeyPair().privateKey);
    const calculatedAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, callData, 0);
    const { transactionHash, contractAddress: udcDeploymentAddress } = await deployContractUDC(
      argentAccountClassHash,
      salt,
      callData,
    );

    await expectEvent(transactionHash, {
      from_address: num.cleanHex(defaultDeployer.address.toString()),
      eventName: "ContractDeployed",
      data: CallData.compile({
        address: udcDeploymentAddress,
        deployer: deployer.address,
        unique: false,
        classHash: argentAccountClassHash,
        calldata: callData,
        salt: salt,
      }),
    });

    expect(calculatedAddress).to.equal(udcDeploymentAddress);
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
    await deployContractUDC(argentAccountClassHash, salt, callData).should.be.rejectedWith(
      "Deployment failed: contract already deployed at address 0x",
    );
  });
});
