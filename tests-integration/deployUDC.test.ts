import { expect } from "chai";
import { AgSigner, declareContract, deployContractUDC, randomKeyPair, starknetSigner } from "./lib";
import { num, hash, CairoOption, CairoOptionVariant, CallData } from "starknet";

const salt = num.toHex(randomKeyPair().privateKey);
const owner = randomKeyPair();
const guardian = randomKeyPair();

describe("Deploy UDC", function () {
  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Calculated contract address should match UDC", async function () {
    const callData = CallData.compile({
      owner: starknetSigner(owner.publicKey),
      guardian: new CairoOption<AgSigner>(CairoOptionVariant.Some, { signer: starknetSigner(guardian.publicKey) }),
    });

    const calculatedAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, callData, 0);
    const udcDeploymentAddress = await deployContractUDC(argentAccountClassHash, salt, callData);

    expect(calculatedAddress).to.equal(udcDeploymentAddress);

    // note about self deployment: As the address we get from self deployment
    // is calculated using calculateContractAddressFromHash
    // there is no need to test that the self deployment address is the
    // same as the when we deploy using the UDC
  });
});
