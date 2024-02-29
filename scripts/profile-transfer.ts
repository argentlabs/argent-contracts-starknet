import { CallData, uint256 } from "starknet";
import {
  deployAccount,
  deployAccountWithoutGuardian,
  provider,
  getEthContract,
  randomEthKeyPair,
  randomKeyPair,
  randomSecp256r1KeyPair,
  deployFixedWebauthnAccount,
  restart,
  declareContract,
  removeFromCache,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const ethContract = await getEthContract();
const recipient = "0xadbe1";

const profiler = newProfiler(provider);

{
  const { account } = await deployAccount();
  ethContract.connect(account);
  await profiler.profile("Account", await ethContract.transfer(recipient, 1));
}

{
  const { account } = await deployAccountWithoutGuardian();
  ethContract.connect(account);
  await profiler.profile("Account w/o guardian", await ethContract.transfer(recipient, 1));
}

{
  const { account } = await deployAccount({ owner: randomEthKeyPair(), guardian: randomKeyPair() });
  ethContract.connect(account);
  await profiler.profile("Eth sig w guardian", await ethContract.transfer(recipient, 1));
}

{
  const { account } = await deployAccount({
    owner: randomSecp256r1KeyPair(),
    guardian: randomKeyPair(),
  });
  ethContract.connect(account);
  await profiler.profile("Secp256r1 w guardian", await ethContract.transfer(recipient, 1));
}

{
  await restart();
  removeFromCache("ArgentAccount");
  const classHash = await declareContract("ArgentAccount");
  const account = await deployFixedWebauthnAccount(classHash);
  const ethContract = await getEthContract();
  ethContract.connect(account);
  const recipient = 69;
  const amount = uint256.bnToUint256(1);
  await profiler.profile(
    "Fixed webauthn",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee: 1e15 }),
  );
}

profiler.printSummary();
profiler.updateOrCheckReport();
