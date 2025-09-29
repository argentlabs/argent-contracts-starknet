import { hash, uint256 } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  Eip191KeyPair,
  EthKeyPair,
  KeyPair,
  LegacyArgentSigner,
  LegacyStarknetKeyPair,
  Secp256r1KeyPair,
  StarknetKeyPair,
  WebauthnOwner,
  deployAccount,
  deployAccountWithoutGuardians,
  deployOpenZeppelinAccount,
  deployer,
  fundAccountCall,
  manager,
  setupSession,
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
const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);
const starknetOwner = new StarknetKeyPair(privateKey);
const guardian = new StarknetKeyPair(42n);
const profilerClassHash = await manager.declareLocalContract("StableAddressDeployer");
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
  const account = await deployAccountUsingProxy({ owner: starknetOwner, salt: "0x3" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - No guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: starknetOwner, guardian, salt: "0x2" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - With guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: starknetOwner, guardian, salt: "0x40" });
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
  strkContract.providerOrAccount = accountWithDappSigner;
  await profiler.profile("Transfer - With Session", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: starknetOwner, guardian, salt: "0x41" });
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
  strkContract.providerOrAccount = accountWithDappSigner;
  await profiler.profile(
    "Transfer - With Session - Caching Values (1)",
    await strkContract.transfer(recipient, amount),
  );
  await profiler.profile("Transfer - With Session - Cached (2)", await strkContract.transfer(recipient, amount));
}

{
  const owner = new WebauthnOwner(privateKey);
  const account = await deployAccountUsingProxy({ owner, guardian, salt: "0x42" });
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
    cacheOwnerGuid: owner.guid,
  });
  strkContract.providerOrAccount = accountWithDappSigner;
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
  const account = await deployAccountUsingProxy({ owner: starknetOwner, salt: "0xF1" });
  account.signer = new LegacyStarknetKeyPair(starknetOwner.privateKey);
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - No guardian (Old Sig)", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: starknetOwner, guardian, salt: "0xF2" });
  account.signer = new LegacyArgentSigner(
    new LegacyStarknetKeyPair(starknetOwner.privateKey),
    new LegacyStarknetKeyPair(guardian.privateKey),
  );
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - With guardian (Old Sig)", await strkContract.transfer(recipient, amount));
}

{
  const { account } = await deployOpenZeppelinAccount({ owner: new LegacyStarknetKeyPair(42n), salt: "0x1" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - OZ account", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: new EthKeyPair(privateKey), guardian, salt: "0x4" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - Eth sig with guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: new Secp256r1KeyPair(privateKey), guardian, salt: "0x5" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - Secp256r1 with guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: new Eip191KeyPair(privateKey), guardian, salt: "0x6" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - Eip161 with guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployAccountUsingProxy({ owner: new WebauthnOwner(privateKey), guardian, salt: "0x8" });
  strkContract.providerOrAccount = account;
  await profiler.profile("Transfer - Webauthn no guardian", await strkContract.transfer(recipient, amount));
}

profiler.printSummary();
profiler.updateOrCheckReport();

async function deployAccountUsingProxy({
  owner,
  guardian,
  salt,
}: {
  owner: KeyPair;
  guardian?: StarknetKeyPair;
  salt: string;
}): Promise<ArgentAccount> {
  const { contract_address } = await deployer.deployContract({ classHash: profilerClassHash, salt });
  const contract = await manager.loadContract(contract_address, profilerClassHash);

  const calls = [];
  const ownersStorageHash = hash.starknetKeccak("owners_storage");
  calls.push(contract.populateTransaction.storage_write(ownersStorageHash, owner.storedValue));
  calls.push(contract.populateTransaction.storage_write(ownersStorageHash + 1n, owner.signerType));

  if (guardian) {
    const guardiansStorageHash = hash.starknetKeccak("guardians_storage");
    calls.push(contract.populateTransaction.storage_write(guardiansStorageHash, guardian.storedValue));
    calls.push(contract.populateTransaction.storage_write(guardiansStorageHash + 1n, guardian.signerType));
  }

  calls.push(contract.populateTransaction.upgrade(latestClassHash));
  calls.push(fundAccountCall(contract_address, fundingAmount, "STRK"));

  await deployer.execute(calls);

  return new ArgentAccount({ provider: manager, address: contract_address, signer: new ArgentSigner(owner, guardian) });
}
