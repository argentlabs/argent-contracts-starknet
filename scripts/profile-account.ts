import {
  declareContract,
  declareFixtureContract,
  deployAccount,
  deployAccountWithoutGuardian,
  deployer,
  deployOldAccount,
  loadContract,
} from "../tests-integration/lib";
import { reportProfile } from "../tests-integration/lib/gas";

const argentAccountClassHash = await declareContract("ArgentAccount");
const oldArgentAccountClassHash = await declareFixtureContract("OldArgentAccount");
const proxyClassHash = await declareFixtureContract("Proxy");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);

const table: Record<string, any> = {};

{
  const name = "Old Account";
  console.log(name);
  const { account } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "New Account";
  console.log(name);
  const { account } = await deployAccount(argentAccountClassHash);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "New Account without guardian";
  console.log(name);
  const { account } = await deployAccountWithoutGuardian(argentAccountClassHash);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

console.table(table);
