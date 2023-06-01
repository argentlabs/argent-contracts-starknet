import {
  declareContract,
  deployAccount,
  deployAccountWithoutGuardian,
  deployer,
  deployOldAccount,
  loadContract,
} from "../tests/lib";
import { profileGasUsage } from "../tests/lib/gas";

const argentAccountClassHash = await declareContract("ArgentAccount");
const oldArgentAccountClassHash = await declareContract("OldArgentAccount");
const proxyClassHash = await declareContract("Proxy");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);

{
  console.log("Old Account");
  const { account } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
  testDappContract.connect(account);
  const receipt = await testDappContract.set_number(42);
  await profileGasUsage(receipt);
}

{
  console.log("New Account");
  const { account } = await deployAccount(argentAccountClassHash);
  testDappContract.connect(account);
  const receipt = await testDappContract.set_number(42);
  await profileGasUsage(receipt);
}

{
  console.log("New Account without guardian");
  const { account } = await deployAccountWithoutGuardian(argentAccountClassHash);
  testDappContract.connect(account);
  const receipt = await testDappContract.set_number(42);
  await profileGasUsage(receipt);
}
