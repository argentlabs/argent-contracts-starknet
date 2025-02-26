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
  fundAccountCall,
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
const profilerClassHash = await manager.declareLocalContract("ProfilerProxy");
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
  const account = await deployProxy({ owner: starknetOwner, salt: "0x3" });
  strkContract.connect(account);
  await profiler.profile("Transfer - No guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployProxy({ owner: starknetOwner, guardian, salt: "0x2" });
  strkContract.connect(account);
  await profiler.profile("Transfer - With guardian", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployProxy({ owner: starknetOwner, guardian, salt: "0x40" });
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
  const account = await deployProxy({ owner: starknetOwner, guardian, salt: "0x41" });

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
  const owner = new WebauthnOwner(privateKey);
  const account = await deployProxy({ owner, guardian, salt: "0x42" });

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
  const account = await deployProxy({ owner: starknetOwner, salt: "0xF1" });

  account.signer = new LegacyStarknetKeyPair(starknetOwner.privateKey);
  strkContract.connect(account);
  await profiler.profile("Transfer - No guardian (Old Sig)", await strkContract.transfer(recipient, amount));
}

{
  const account = await deployProxy({ owner: starknetOwner, guardian, salt: "0xF2" });

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
  const owner = new EthKeyPair(privateKey);
  const account = await deployProxy({ owner, guardian, salt: "0x4" });

  strkContract.connect(account);
  await profiler.profile("Transfer - Eth sig with guardian", await strkContract.transfer(recipient, amount));
}

{
  const owner = new Secp256r1KeyPair(privateKey);
  const account = await deployProxy({ owner, guardian, salt: "0x5" });

  strkContract.connect(account);
  await profiler.profile("Transfer - Secp256r1 with guardian", await strkContract.transfer(recipient, amount));
}

{
  const owner = new Eip191KeyPair(privateKey);
  const account = await deployProxy({ owner, guardian, salt: "0x6" });

  strkContract.connect(account);
  await profiler.profile("Transfer - Eip161 with guardian", await strkContract.transfer(recipient, amount));
}

{
  const owner = new WebauthnOwner(privateKey);
  const account = await deployProxy({ owner, guardian, salt: "0x8" });

  strkContract.connect(account);
  await profiler.profile("Transfer - Webauthn no guardian", await strkContract.transfer(recipient, amount));
}

profiler.printSummary();
profiler.updateOrCheckReport();

async function deployProxy({ owner, guardian, salt }: { owner: KeyPair; guardian?: StarknetKeyPair; salt: string }) {
  const { contract_address } = await deployer.deployContract({ classHash: profilerClassHash, salt });
  const contract = await manager.loadContract(contract_address, profilerClassHash);
  const calls = [];

  calls.push(contract.populateTransaction.write_storage(hash.starknetKeccak("owners_storage"), owner.storedValue));
  calls.push(contract.populateTransaction.write_storage(hash.starknetKeccak("owners_storage") + 1n, owner.signerType));

  if (guardian) {
    calls.push(contract.populateTransaction.write_storage(hash.starknetKeccak("guardians_storage"), guardian.storedValue));
    calls.push(contract.populateTransaction.write_storage(hash.starknetKeccak("guardians_storage") + 1n, guardian.signerType));
  }

  calls.push(contract.populateTransaction.upgrade(latestClassHash));
  calls.push(fundAccountCall(contract_address, fundingAmount, "STRK"));

  await deployer.execute(calls);

  return new ArgentAccount(
    manager,
    contract_address,
    new ArgentSigner(owner, guardian),
    "1",
    RPC.ETransactionVersion.V3,
  );
}
