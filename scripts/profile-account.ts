import { InvokeFunctionResponse } from "starknet";
import {
  declareContract,
  declareFixtureContract,
  deployAccount,
  deployAccountWithoutGuardian,
  deployer,
  deployOldAccount,
  loadContract,
} from "../tests/lib";
import { profileGasUsage } from "../tests/lib/gas";

const argentAccountClassHash = await declareContract("ArgentAccount");
const oldArgentAccountClassHash = await declareFixtureContract("OldArgentAccount");
const proxyClassHash = await declareFixtureContract("Proxy");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);

const ethusd = 1600n;

const table: Record<string, any> = {};
const gwei = 10n ** 9n;

async function reportProfile(name: string, response: InvokeFunctionResponse) {
  const report = await profileGasUsage(response);
  const { actualFee, gasUsed, computationGas, l1CalldataGas, executionResources } = report;
  console.dir(report, { depth: null });
  const feeUsd = Number(actualFee) / Number(ethusd * gwei);
  table[name] = {
    actualFee: Number(actualFee),
    feeUsd: Number(feeUsd.toFixed(2)),
    gasUsed: Number(gasUsed),
    computationGas: Number(computationGas),
    l1CalldataGas: Number(l1CalldataGas),
    ...executionResources,
  };
}

{
  const name = "Old Account";
  console.log(name);
  const { account } = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
  testDappContract.connect(account);
  await reportProfile(name, await testDappContract.set_number(42));
}

{
  const name = "New Account";
  console.log(name);
  const { account } = await deployAccount(argentAccountClassHash);
  testDappContract.connect(account);
  await reportProfile(name, await testDappContract.set_number(42));
}

{
  const name = "New Account without guardian";
  console.log(name);
  const { account } = await deployAccountWithoutGuardian(argentAccountClassHash);
  testDappContract.connect(account);
  await reportProfile(name, await testDappContract.set_number(42));
}

console.table(table);
