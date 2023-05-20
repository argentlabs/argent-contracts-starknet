import { Account, CallData, Contract, ec, hash } from "starknet";
import { ArgentSigner } from "./argentSigner";
import { deployerAccount, provider } from "./constants";
import { fundAccount } from "./devnet";
import { loadContract, randomPrivateKey } from "./lib";

// This is only for TESTS purposes and shouldn't be used in production
export interface ArgentWallet {
  account: Account;
  accountContract: Contract;
  ownerPrivateKey: string;
  guardianPrivateKey?: string;
  guardianBackupPrivateKey?: string;
}

export async function deployOldAccount(
  proxyClassHash: string,
  oldArgentAccountClassHash: string,
): Promise<ArgentWallet> {
  const ownerPrivateKey = randomPrivateKey();
  const guardianPrivateKey = randomPrivateKey();
  const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);
  const guardianPublicKey = ec.starkCurve.getStarkKey(guardianPrivateKey);

  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ owner: ownerPublicKey, guardian: guardianPublicKey }),
  });

  const contractAddress = hash.calculateContractAddressFromHash(ownerPublicKey, proxyClassHash, constructorCalldata, 0);

  const account = new Account(provider, contractAddress, ownerPrivateKey);
  account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);

  await fundAccount(account.address);
  const { transaction_hash } = await account.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: ownerPublicKey,
  });
  await deployerAccount.waitForTransaction(transaction_hash);
  const accountContract = await loadContract(account.address);
  return { account, accountContract, ownerPrivateKey, guardianPrivateKey };
}

async function deployAccountInner(
  argentAccountClassHash: string,
  ownerPrivateKey: string,
  guardianPrivateKey?: string,
): Promise<Account> {
  const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

  const guardianPublicKey = guardianPrivateKey ? ec.starkCurve.getStarkKey(guardianPrivateKey) : "0";

  const constructorCalldata = CallData.compile({ owner: ownerPublicKey, guardian: guardianPublicKey });

  const contractAddress = hash.calculateContractAddressFromHash(
    ownerPublicKey,
    argentAccountClassHash,
    constructorCalldata,
    0,
  );
  await fundAccount(contractAddress);
  const account = new Account(provider, contractAddress, ownerPrivateKey, "1");
  if (guardianPrivateKey) {
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

export async function deployAccount(argentAccountClassHash: string): Promise<ArgentWallet> {
  const ownerPrivateKey = randomPrivateKey();
  const guardianPrivateKey = randomPrivateKey();
  const account = await deployAccountInner(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
  const accountContract = await loadContract(account.address);

  return { account, accountContract, ownerPrivateKey, guardianPrivateKey };
}

export async function deployAccountWithoutGuardian(argentAccountClassHash: string): Promise<ArgentWallet> {
  const ownerPrivateKey = randomPrivateKey();
  const account = await deployAccountInner(argentAccountClassHash, ownerPrivateKey);
  const accountContract = await loadContract(account.address);

  return { account, accountContract, ownerPrivateKey };
}

export async function deployAccountWithGuardianBackup(argentAccountClassHash: string): Promise<ArgentWallet> {
  const guardianBackupPrivateKey = randomPrivateKey();
  const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey);

  const wallet = await deployAccount(argentAccountClassHash);
  await wallet.account.execute(
    wallet.accountContract.populateTransaction.change_guardian_backup(guardianBackupPublicKey),
  );

  wallet.account.signer = new ArgentSigner(wallet.ownerPrivateKey, guardianBackupPrivateKey);
  wallet.guardianBackupPrivateKey = guardianBackupPrivateKey;
  return wallet;
}

export async function upgradeAccount(accountToUpgrade: Account, argentAccountClassHash: string) {
  const { transaction_hash: transferTxHash } = await accountToUpgrade.execute({
    contractAddress: accountToUpgrade.address,
    entrypoint: "upgrade",
    calldata: CallData.compile({ implementation: argentAccountClassHash, calldata: ["0"] }),
  });
  await provider.waitForTransaction(transferTxHash);
}
