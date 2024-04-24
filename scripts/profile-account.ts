import { declareContract, declareFixtureContract, deployLegacyMultisig, provider, upgradeAccount } from "../lib";
import { newProfiler } from "../lib/gas";

const profiler = newProfiler(provider);

for (const threshold of [1, 3, 10]) {
  const { account } = await deployLegacyMultisig(await declareFixtureContract("ArgentMultisig-0.1.0"), threshold);
  const currentImpl = await declareContract("ArgentMultisigAccount");

  const tx = await upgradeAccount(account, currentImpl);

  await profiler.profile(`Acc ${threshold}`, tx);
}

profiler.printSummary();
