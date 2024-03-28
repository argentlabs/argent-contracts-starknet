import { CallData, uint256 } from "starknet";
import {
  Eip191KeyPair,
  EthKeyPair,
  LegacyArgentSigner,
  LegacyStarknetKeyPair,
  Secp256r1KeyPair,
  StarknetKeyPair,
  WebauthnOwner,
  clearCache,
  deployAccount,
  deployAccountWithoutGuardian,
  deployOldAccount,
  deployOpenZeppelinAccount,
  getEthContract,
  provider,
  restart,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const profiler = newProfiler(provider);
const fundingAmount = 2e16;
const maxFee = 1e16;

let privateKey: string;
if (provider.isDevnet) {
  // With the KeyPairs hardcoded, we gotta reset to avoid some issues
  await restart();
  privateKey = "0x1";
  clearCache();
} else {
  privateKey = new StarknetKeyPair().privateKey;
}

const ethContract = await getEthContract();
const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);
const starknetOwner = new StarknetKeyPair(privateKey);
const guardian = new StarknetKeyPair(42n);

{
  const { transactionHash } = await deployAccountWithoutGuardian({
    owner: starknetOwner,
    selfDeploy: true,
    salt: "0x200",
    fundingAmount,
  });
  await profiler.profile("Deploy no guardian", transactionHash);
}

{
  const { transactionHash } = await deployAccount({
    owner: starknetOwner,
    guardian,
    selfDeploy: true,
    salt: "0xDE",
    fundingAmount,
  });
  await profiler.profile("Deploy with guardian", transactionHash);
}

{
  const { deployTxHash } = await deployOpenZeppelinAccount({ owner: new LegacyStarknetKeyPair(42n), salt: "0xDE" });
  await profiler.profile("Deploy OZ", deployTxHash);
}

{
  const { account } = await deployOldAccount();
  ethContract.connect(account);
  await profiler.profile("Old account with guardian", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccountWithoutGuardian({
    owner: starknetOwner,
    salt: "0x3",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Account no guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccount({
    owner: starknetOwner,
    guardian,
    salt: "0x2",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Account with guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccountWithoutGuardian({
    owner: starknetOwner,
    salt: "0xF1",
    fundingAmount,
  });
  account.signer = new LegacyStarknetKeyPair(starknetOwner.privateKey);
  ethContract.connect(account);
  await profiler.profile(
    "Account no guardian. Old Sig",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployAccount({
    owner: starknetOwner,
    guardian,
    salt: "0xF2",
    fundingAmount,
  });
  account.signer = new LegacyArgentSigner(
    new LegacyStarknetKeyPair(starknetOwner.privateKey),
    new LegacyStarknetKeyPair(guardian.privateKey),
  );
  ethContract.connect(account);
  await profiler.profile(
    "Account with guardian. Old Sig",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

{
  const { account } = await deployOpenZeppelinAccount({ owner: new LegacyStarknetKeyPair(42n), salt: "0x1" });
  ethContract.connect(account);
  await profiler.profile("OZ account", await ethContract.transfer(recipient, amount));
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
    "Eth sig with guardian",
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
    "Secp256r1 with guardian",
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

{
  const { account } = await deployAccount({
    owner: new WebauthnOwner(privateKey),
    guardian,
    salt: "0x7",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile(
    "Webauthn no guardian",
    await ethContract.invoke("transfer", CallData.compile([recipient, amount]), { maxFee }),
  );
}

profiler.printSummary();
profiler.updateOrCheckReport();
