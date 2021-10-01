const { expect } = require("chai");
const { getStarknetContract } = require("hardhat");

describe("Starknet", function () {
  this.timeout(300_000); // 5 min
  it("Should work", async function () {
    const contract = await getStarknetContract("ArgentAccount");
    await contract.deploy();
    console.log("Deployed at", contract.address);
    
    expect(0).to.equal(0);
  });
});