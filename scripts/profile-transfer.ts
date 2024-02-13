import {
  deployAccount,
  deployAccountWithoutGuardian,
  provider,
  getEthContract,
  getStrkContract,
  randomEthKeyPair,
  randomKeyPair,
  randomSecp256r1KeyPair,
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
//   await profiler.profile("Account w/o guardian - transfer", await ethContract.transfer(recipient, 1));
// }

// {
//   const { account } = await deployAccount({ useTxV3: true });
//   strkContract.connect(account);
//   await profiler.profile("TxV3 w/ guardian - transfer", await strkContract.transfer(recipient, 1));
// }

// {
//   const { account } = await deployAccount({ owner: randomEthKeyPair(), guardian: randomKeyPair() });
//   ethContract.connect(account);
//   await profiler.profile("Eth sig w/ guardian - transfer", await ethContract.transfer(recipient, 1));
// }

{
  const { account } = await deployAccount({
    owner: randomSecp256r1KeyPair(),
    guardian: randomKeyPair(),
  });
  ethContract.connect(account);
  await profiler.profile("Secp256r1 w/ guardian - transfer", await ethContract.transfer(recipient, 1));
}

profiler.printSummary();
profiler.updateOrCheckReport();
