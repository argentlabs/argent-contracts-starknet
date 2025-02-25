import { hash, RPC, uint256 } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  deployAccount,
  deployAccountWithoutGuardians,
  deployer,
  deployOldAccountWithProxy,
  deployOpenZeppelinAccount,
  Eip191KeyPair,
  EthKeyPair,
  fundAccount,
  KeyPair,
  LegacyArgentSigner,
  LegacyStarknetKeyPair,
  manager,
  Secp256r1KeyPair,
  setupSession,
  StarknetKeyPair,
  WebauthnOwner,
} from "../lib";
import { newProfiler } from "../lib/gas";

const profiler = newProfiler(manager);
const fundingAmount = 1e18;

let privateKey: string;
if (manager.isDevnet) {
  // With the KeyPairs hardcoded, we gotta reset to avoid some issues
  await manager.restart();
  privateKey = "0x1";
  manager.clearClassCache();
} else {
  privateKey = new StarknetKeyPair().privateKey;
}

const strkContract = await manager.tokens.strkContract();
const ethContract = await manager.tokens.ethContract();
const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);
const starknetOwner = new StarknetKeyPair(privateKey);
const guardian = new StarknetKeyPair(42n);
const profilerClassHash = await manager.declareLocalContract("ArgentAccountProfile");
const latestClassHash = await manager.declareLocalContract("ArgentAccount");

{
  const { transactionHash } = await deployAccountWithoutGuardians({
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
  const { account } = await deployOldAccountWithProxy(
    new LegacyStarknetKeyPair(privateKey),
    new LegacyStarknetKeyPair(guardian.privateKey),
    "0xDE",
  );
  ethContract.connect(account);
  await profiler.profile("Transfer - Old account with guardian", await ethContract.transfer(recipient, amount));
}

{
  const account = await deploy(starknetOwner, "0x3");
  strkContract.connect(account);
  await profiler.profile("Transfer - No guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deploy(starknetOwner, "0x2", guardian);
  strkContract.connect(account);
  await profiler.profile("Transfer - With guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deploy(starknetOwner, "0x40",guardian);
  const sessionTime = 1710167933n;
  await manager.setTime(sessionTime);
  const dappKey = new StarknetKeyPair(39n);
  const allowedMethods = [{ "Contract Address": strkContract.address, selector: "transfer" }];

  const { accountWithDappSigner } = await setupSession({
    guardian: guardian as StarknetKeyPair,
    dappKey,
    account,
    allowedMethods,
    expiry: sessionTime + 150n,
  });
  strkContract.connect(accountWithDappSigner);
  await profiler.profile("Transfer - With Session", await strkContract.transfer(recipient, amount));
}

{
  const account = await deploy(starknetOwner, "0x41", guardian);

  const sessionTime = 1710167933n;
  await manager.setTime(sessionTime);
  const dappKey = new StarknetKeyPair(39n);
  const allowedMethods = [{ "Contract Address": strkContract.address, selector: "transfer" }];

  const { accountWithDappSigner } = await setupSession({
    guardian: guardian as StarknetKeyPair,
    dappKey,
    account,
    allowedMethods,
    expiry: sessionTime + 150n,
    cacheOwnerGuid: starknetOwner.guid,
  });
  strkContract.connect(accountWithDappSigner);
  await profiler.profile(
    "Transfer - With Session - Caching Values (1)",
    await strkContract.transfer(recipient, amount),
  );
  await profiler.profile("Transfer - With Session - Cached (2)", await strkContract.transfer(recipient, amount));
}

{
  const key = new WebauthnOwner(privateKey);
  const account = await deploy(key, "0x42",guardian);

  const sessionTime = 1710167933n;
  await manager.setTime(sessionTime);
  const dappKey = new StarknetKeyPair(39n);
  const allowedMethods = [{ "Contract Address": strkContract.address, selector: "transfer" }];

  const { accountWithDappSigner } = await setupSession({
    guardian: guardian as StarknetKeyPair,
    dappKey,
    account,
    allowedMethods,
    expiry: sessionTime + 150n,
    cacheOwnerGuid: key.guid,
  });
  strkContract.connect(accountWithDappSigner);
  await profiler.profile(
    "Transfer - With Session (Webauthn owner) - Caching Values (1)",
    await strkContract.transfer(recipient, amount),
  );
  await profiler.profile(
    "Transfer - With Session (Webauthn owner) - Cached (2)",
    await strkContract.transfer(recipient, amount),
  );
}

{
  const account = await deploy(starknetOwner, "0xF1");

  account.signer = new LegacyStarknetKeyPair(starknetOwner.privateKey);
  strkContract.connect(account);
  await profiler.profile("Transfer - No guardian (Old Sig)", await strkContract.transfer(recipient, amount));
}

{
  const account = await deploy(starknetOwner, "0xF2", guardian);

  account.signer = new LegacyArgentSigner(
    new LegacyStarknetKeyPair(starknetOwner.privateKey),
    new LegacyStarknetKeyPair(guardian.privateKey),
  );
  strkContract.connect(account);
  await profiler.profile("Transfer - With guardian (Old Sig)", await strkContract.transfer(recipient, amount));
}

{
  const { account } = await deployOpenZeppelinAccount({ owner: new LegacyStarknetKeyPair(42n), salt: "0x1" });
  strkContract.connect(account);
  await profiler.profile("Transfer - OZ account", await strkContract.transfer(recipient, amount));
}

{
  const key = new EthKeyPair(privateKey);
  const account = await deploy(key, "0x4", guardian);

  strkContract.connect(account);
  await profiler.profile("Transfer - Eth sig with guardian", await strkContract.transfer(recipient, amount));
}

{
  const key = new Secp256r1KeyPair(privateKey);
  const account = await deploy(key, "0x5", guardian);

  strkContract.connect(account);
  await profiler.profile("Transfer - Secp256r1 with guardian", await strkContract.transfer(recipient, amount));
}

{
  const key = new Eip191KeyPair(privateKey);
  const account = await deploy(key, "0x6", guardian);

  strkContract.connect(account);
  await profiler.profile("Transfer - Eip161 with guardian", await strkContract.transfer(recipient, amount));
}

{
  const key = new WebauthnOwner(privateKey);
  const account = await deploy(key, "0x8", guardian);

  strkContract.connect(account);
  await profiler.profile("Transfer - Webauthn no guardian", await strkContract.transfer(recipient, amount));
}

profiler.printSummary();
profiler.updateOrCheckReport();

async function deploy(owner: KeyPair, salt: string, guardian?: StarknetKeyPair) {
  const { contract_address } = await deployer.deployContract({ classHash: profilerClassHash, salt });
  const contract = await manager.loadContract(contract_address, profilerClassHash);
  contract.connect(deployer);
  await contract.fill(hash.starknetKeccak("owners_storage"), owner.storedValue);
  // (ugly version atm)
  // We could add a fn, isStoredAsGuid, if no => get type
  if (owner instanceof EthKeyPair) {
    await contract.fill(hash.starknetKeccak("owners_storage") + 1n, "0x1");
  } else if (owner instanceof Secp256r1KeyPair) {
    await contract.fill(hash.starknetKeccak("owners_storage") + 1n, "0x2");
  } else if (owner instanceof Eip191KeyPair) {
    await contract.fill(hash.starknetKeccak("owners_storage") + 1n, "0x3");
  } else if (owner instanceof WebauthnOwner) {
    await contract.fill(hash.starknetKeccak("owners_storage") + 1n, "0x4");
  }

  if (guardian) {
    await contract.fill(hash.starknetKeccak("guardians_storage"), guardian.storedValue);
  }
  await contract.upgrade(latestClassHash);
  await fundAccount(contract_address, fundingAmount, "STRK");
  return new ArgentAccount(
    manager,
    contract_address,
    new ArgentSigner(owner, guardian),
    "1",
    RPC.ETransactionVersion.V3,
  );
}
