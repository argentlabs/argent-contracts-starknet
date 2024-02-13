import {
  deployAccount,
  deployAccountWithoutGuardian,
  provider,
  getEthContract,
  getStrkContract,
  randomEthKeyPair,
  randomKeyPair,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const ethContract = await getEthContract();
const strkContract = await getStrkContract();
const recipient = "0xadbe1";

const profiler = newProfiler(provider);

// {
//   const { account } = await deployAccount();
//   ethContract.connect(account);
//   await profiler.profile("Account - transfer", await ethContract.transfer(recipient, 1));
// }

// {
//   const { account } = await deployAccountWithoutGuardian();
//   ethContract.connect(account);
//   await profiler.profile("Account without guardian - transfer", await ethContract.transfer(recipient, 1));
// }

// {
//   const { account } = await deployAccount({ useTxV3: true });
//   strkContract.connect(account);
//   await profiler.profile("Account (Using txV3) - transfer", await strkContract.transfer(recipient, 1));
// }

// {
//   const { account } = await deployAccount({ owner: randomEthKeyPair(), guardian: randomKeyPair() });
//   ethContract.connect(account);
//   await profiler.profile("Account w g (owner ETH signature) - transfer", await ethContract.transfer(recipient, 1));
// }

{
  const { account } = await deployAccount({ owner: randomEthKeyPair(), guardian: randomKeyPair() });
  ethContract.connect(account);
  await profiler.profile(
    "Account w g (owner Secp256R1 signature) - transfer",
    await ethContract.transfer(recipient, 1),
  );
}

profiler.printSummary();
profiler.updateOrCheckReport();
