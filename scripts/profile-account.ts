import { CallData, uint256 } from "starknet";
import {
  deployAccount,
  deployAccountWithoutGuardian,
  provider,
  getEthContract,
  restart,
  removeFromCache,
  deployOldAccount,
  LegacyStarknetKeyPair,
  signChangeOwnerMessage,
  starknetSignatureType,
  StarknetKeyPair,
  EthKeyPair,
  Secp256r1KeyPair,
  Eip191KeyPair,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const profiler = newProfiler(provider);
const fundingAmount = 15e15;
const maxFee = 12e15;

let privateKey: string;
if (provider.isDevnet) {
  // With the KeyPairs hardcoded, we gotta reset to avoid some issues
  await restart();
  privateKey = "0x1";
} else {
  privateKey = new StarknetKeyPair().privateKey;
}

removeFromCache("Proxy");
removeFromCache("OldArgentAccount");
removeFromCache("ArgentAccount");

const ethContract = await getEthContract();
const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);
const starknetOwner = new StarknetKeyPair(privateKey);
const guardian = new StarknetKeyPair(42n);

// {
//   const { account } = await deployOldAccount();
//   ethContract.connect(account);
//   await profiler.profile("Old account", await ethContract.transfer(recipient, amount));
// }

// {
//   const { account, accountContract } = await deployAccount({
//     owner: starknetOwner,
//     guardian,
//     salt: "0x1",
//   });
//   const owner = await accountContract.get_owner();
//   const newOwner = new LegacyStarknetKeyPair();
//   const chainId = await provider.getChainId();
//   const [r, s] = await signChangeOwnerMessage(account.address, owner, newOwner, chainId);
//   await profiler.profile(
//     "Change owner",
//     await accountContract.change_owner(starknetSignatureType(newOwner.publicKey, r, s)),
//   );
// }

{
  const { account } = await deployAccount({
    owner: starknetOwner,
    guardian,
    salt: "0x2",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Account",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccountWithoutGuardian({
    owner: starknetOwner,
    salt: "0x3",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Account w/o guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccount({
    owner: new EthKeyPair(privateKey),
    guardian,
    salt: "0x4",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Eth sig w guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccount({
    owner: new Secp256r1KeyPair(privateKey),
    guardian,
    salt: "0x5",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Secp256r1 w guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccount({
    owner: new Eip191KeyPair(privateKey),
    guardian,
    salt: "0x6",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Eip161 with guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

// {
//   await restart();
//   removeFromCache("ArgentAccount");
//   const classHash = await declareContract("ArgentAccount");
//   const account = await deployFixedWebauthnAccount(classHash);
//   const ethContract = await getEthContract();
//   ethContract.connect(account);
//   const recipient = 69;
//   await profiler.profile(
//     "Fixed webauthn w/o guardian",
//     await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee: 1e15 }),
//   );
// }

profiler.printSummary();
profiler.updateOrCheckReport();
