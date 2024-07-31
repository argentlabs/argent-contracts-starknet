import assert from "assert";
import { uint256 } from "starknet";
import {
  Eip191KeyPair,
  EthKeyPair,
  LegacyArgentSigner,
  LegacyStarknetKeyPair,
  Secp256r1KeyPair,
  StarknetKeyPair,
  WebauthnOwnerSyscall,
  deployAccount,
  deployAccountWithoutGuardian,
  deployOldAccount,
  deployOpenZeppelinAccount,
  manager,
  setupSession,
} from "../lib";
import { newProfiler } from "../lib/gas";

const profiler = newProfiler(manager);
const fundingAmount = 2e16;

let privateKey: string;
if (manager.isDevnet) {
  // With the KeyPairs hardcoded, we gotta reset to avoid some issues
  await manager.restart();
  privateKey = "0x1";
  manager.clearClassCache();
} else {
  privateKey = new StarknetKeyPair().privateKey;
}

const ethContract = await manager.tokens.ethContract();
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
  await profiler.profile("Deploy - No guardian", transactionHash);
}

{
  const { transactionHash } = await deployAccount({
    owner: starknetOwner,
    guardian,
    selfDeploy: true,
    salt: "0xDE",
    fundingAmount,
  });
  await profiler.profile("Deploy - With guardian", transactionHash);
}

{
  const { deployTxHash } = await deployOpenZeppelinAccount({ owner: new LegacyStarknetKeyPair(42n), salt: "0xDE" });
  await profiler.profile("Deploy - OZ", deployTxHash);
}

{
  const { account } = await deployOldAccount(
    new LegacyStarknetKeyPair(privateKey),
    new LegacyStarknetKeyPair(guardian.privateKey),
    "0xDE",
  );
  ethContract.connect(account);
  await profiler.profile("Transfer - Old account with guardian", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccountWithoutGuardian({
    owner: starknetOwner,
    salt: "0x3",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile("Transfer - No guardian", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccount({
    owner: starknetOwner,
    guardian,
    salt: "0x2",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile("Transfer - With guardian", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccount({
    owner: starknetOwner,
    guardian,
    salt: "0x40",
    fundingAmount,
  });
  const sessionTime = 1710167933n;
  await manager.setTime(sessionTime);
  const dappKey = new StarknetKeyPair(39n);
  const allowedMethod = [{ "Contract Address": ethContract.address, selector: "transfer" }];

  const { accountWithDappSigner } = await setupSession(
    guardian as StarknetKeyPair,
    account,
    allowedMethod,
    sessionTime + 150n,
    dappKey,
  );
  ethContract.connect(accountWithDappSigner);
  await profiler.profile("Transfer - With Session", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccount({
    owner: starknetOwner,
    guardian,
    salt: "0x41",
    fundingAmount,
  });
  const sessionTime = 1710167933n;
  await manager.setTime(sessionTime);
  const dappKey = new StarknetKeyPair(39n);
  const allowedMethod = [{ "Contract Address": ethContract.address, selector: "transfer" }];

  const { accountWithDappSigner } = await setupSession(
    guardian as StarknetKeyPair,
    account,
    allowedMethod,
    sessionTime + 150n,
    dappKey,
    true,
  );
  ethContract.connect(accountWithDappSigner);
  await profiler.profile("Transfer - With Session - Caching Values (1)", await ethContract.transfer(recipient, amount));
  await profiler.profile("Transfer - With Session - Cached (2)", await ethContract.transfer(recipient, amount));
}

{
  const classHash = await manager.declareFixtureContract("Sha256Cairo0");
  assert(BigInt(classHash) === 0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6dn);
  const { account } = await deployAccount({
    owner: new WebauthnOwnerSyscall(privateKey),
    guardian,
    salt: "0x42",
    fundingAmount,
  });
  const sessionTime = 1710167933n;
  await manager.setTime(sessionTime);
  const dappKey = new StarknetKeyPair(39n);
  const allowedMethod = [{ "Contract Address": ethContract.address, selector: "transfer" }];

  const { accountWithDappSigner } = await setupSession(
    guardian as StarknetKeyPair,
    account,
    allowedMethod,
    sessionTime + 150n,
    dappKey,
    true,
  );
  ethContract.connect(accountWithDappSigner);
  await profiler.profile(
    "Transfer - With Session (Webauthn owner) - Caching Values (1)",
    await ethContract.transfer(recipient, amount),
  );
  await profiler.profile(
    "Transfer - With Session (Webauthn owner) - Cached (2)",
    await ethContract.transfer(recipient, amount),
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
  await profiler.profile("Transfer - No guardian (Old Sig)", await ethContract.transfer(recipient, amount));
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
  await profiler.profile("Transfer - With guardian (Old Sig)", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployOpenZeppelinAccount({ owner: new LegacyStarknetKeyPair(42n), salt: "0x1" });
  ethContract.connect(account);
  await profiler.profile("Transfer - OZ account", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccount({
    owner: new EthKeyPair(privateKey),
    guardian,
    salt: "0x4",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile("Transfer - Eth sig with guardian", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccount({
    owner: new Secp256r1KeyPair(privateKey),
    guardian,
    salt: "0x5",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile("Transfer - Secp256r1 with guardian", await ethContract.transfer(recipient, amount));
}

{
  const { account } = await deployAccount({
    owner: new Eip191KeyPair(privateKey),
    guardian,
    salt: "0x6",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile("Transfer - Eip161 with guardian", await ethContract.transfer(recipient, amount));
}

{
  const classHash = await manager.declareFixtureContract("Sha256Cairo0");
  assert(BigInt(classHash) === 0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6dn);
  const { account } = await deployAccount({
    owner: new WebauthnOwnerSyscall(privateKey),
    guardian,
    salt: "0x7",
    fundingAmount,
  });
  ethContract.connect(account);
  await profiler.profile("Transfer - Webauthn no guardian", await ethContract.transfer(recipient, amount));
}

profiler.printSummary();
profiler.updateOrCheckReport();
