import { Contract } from "starknet";
import { declareContract, deployAccount, deployer, deployOldAccount, loadContract } from "./lib";
import { profileGasUsage } from "./lib/gas";

describe.skip("ArgentAccount: Profile", function () {
  let argentAccountClassHash: string;
  let testDappContract: Contract;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    oldArgentAccountClassHash = await declareContract("OldArgentAccount");
    proxyClassHash = await declareContract("Proxy");
    const testDappClassHash = await declareContract("TestDapp");
    const { contract_address } = await deployer.deployContract({
      classHash: testDappClassHash,
    });
    testDappContract = await loadContract(contract_address);
  });

  it("TestDapp Old account", async function () {
    const { account } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
    testDappContract.connect(account);
    const receipt = await testDappContract.set_number(42);
    await profileGasUsage(receipt);
  });

  it("TestDapp", async function () {
    console.log("New Account");
    const { account } = await deployAccount(argentAccountClassHash);
    testDappContract.connect(account);
    const receipt = await testDappContract.set_number(42);
    await profileGasUsage(receipt);
  });
});
