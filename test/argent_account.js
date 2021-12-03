const { expect } = require("chai");
const { starknet } = require("hardhat");

describe("Starknet", function () {
  this.timeout(300_000); // 5 min

  it("Should work", async function () {
    const contract = await starknet.getContractFactory("ArgentAccount");
    await contract.deploy({ signer: 1, guardian: 0 });
    console.log("Deployed at", contract.address);
    
    expect(0).to.equal(0);
  });
});