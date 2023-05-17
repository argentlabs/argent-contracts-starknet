import { Account, CallData, Contract, Signer, ec, hash, stark } from "starknet";
import { ArgentSigner, ConcatSigner } from "./argentSigner";
import { deployerAccount, provider } from "./constants";
import { fundAccount } from "./devnetInteraction";
import { loadContract } from "./lib";

// This is only for TESTS purposes
export type AccountLeaked = {
  account: Account;
  accountContract: Contract;
  ownerPrivateKey: string;
  guardianPrivateKey?: string;
  guardianBackupPrivateKey?: string;
};

async function deployOldAccount(
  proxyClassHash: string,
  oldArgentAccountClassHash: string,
  guardianPrivateKey = "0",
): Promise<AccountLeaked> {
  const ownerPrivateKey = stark.randomAddress();
  const publicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);
  const guardianPublicKey = guardianPrivateKey != "0" ? ec.starkCurve.getStarkKey(guardianPrivateKey) : "0";

  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ owner: publicKey, guardian: guardianPublicKey }),
  });

  const contractAddress = hash.calculateContractAddressFromHash(publicKey, proxyClassHash, constructorCalldata, 0);

  const account = new Account(provider, contractAddress, ownerPrivateKey);
  await fundAccount(account.address);
  if (guardianPrivateKey != "0") {
    account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
  }
  const { transaction_hash } = await account.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: publicKey,
  });
  await deployerAccount.waitForTransaction(transaction_hash);
  const accountContract = await loadContract(account.address);
  return { account, accountContract, ownerPrivateKey };
}

// TODO Ideally this fn shouldn't beused anymore and we should only be using deployAccountV2 everywhere which we will then be able to rename
async function deployAccount(
  argentAccountClassHash: string,
  ownerPrivateKey?: string,
  guardianPrivateKey = "0",
): Promise<Account> {
  ownerPrivateKey = ownerPrivateKey || stark.randomAddress();
  const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);
  const guardianPublicKey = guardianPrivateKey != "0" ? ec.starkCurve.getStarkKey(guardianPrivateKey) : "0";

  const constructorCalldata = CallData.compile({ owner: ownerPublicKey, guardian: guardianPublicKey });

  const contractAddress = hash.calculateContractAddressFromHash(
    ownerPublicKey,
    argentAccountClassHash,
    constructorCalldata,
    0,
  );
  await fundAccount(contractAddress);
  const account = new Account(provider, contractAddress, ownerPrivateKey, "1");
  if (guardianPrivateKey != "0") {
    account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
  }
  const { transaction_hash } = await account.deploySelf({
    classHash: argentAccountClassHash,
    constructorCalldata,
    addressSalt: ownerPublicKey,
  });

  await deployerAccount.waitForTransaction(transaction_hash);
  return account;
}

async function deployAccountV2(argentAccountClassHash: string): Promise<AccountLeaked> {
  const ownerPrivateKey = stark.randomAddress();
  const guardianPrivateKey = stark.randomAddress();
  const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);

  account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
  const accountContract = await loadContract(account.address);
  return {
    account,
    accountContract,
    ownerPrivateKey,
    guardianPrivateKey,
  };
}

async function deployAccountWithoutGuardian(argentAccountClassHash: string): Promise<AccountLeaked> {
  const ownerPrivateKey = stark.randomAddress();
  const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, "0");

  account.signer = new Signer(ownerPrivateKey);
  const accountContract = await loadContract(account.address);
  return {
    account,
    accountContract,
    ownerPrivateKey,
  };
}

async function deployAccountWithGuardianBackup(argentAccountClassHash: string): Promise<AccountLeaked> {
  const guardianBackupPrivateKey = stark.randomAddress();
  const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey);

  const accountLeaked = await deployAccountV2(argentAccountClassHash);
  await accountLeaked.account.execute(
    accountLeaked.accountContract.populateTransaction.change_guardian_backup(guardianBackupPublicKey),
  );
  accountLeaked.guardianBackupPrivateKey = guardianBackupPrivateKey;
  return accountLeaked;
}

async function upgradeAccount(accountToUpgrade: Account, argentAccountClassHash: string) {
  const { transaction_hash: transferTxHash } = await accountToUpgrade.execute({
    contractAddress: accountToUpgrade.address,
    entrypoint: "upgrade",
    calldata: CallData.compile({ implementation: argentAccountClassHash, calldata: ["0"] }),
  });
  await provider.waitForTransaction(transferTxHash);
}

export {
  deployAccount,
  deployAccountV2,
  deployAccountWithGuardianBackup,
  deployAccountWithoutGuardian,
  deployOldAccount,
  upgradeAccount,
};
