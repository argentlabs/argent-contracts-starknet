import { Account, CallData, Contract, InvokeTransactionReceiptResponse, RawCalldata, ec, hash } from "starknet";
import { loadContract } from "./contracts";
import { fundAccount } from "./devnet";
import { provider } from "./provider";
import { ArgentSigner, randomPrivateKey } from "./signers";

// This is only for TESTS purposes and shouldn't be used in production
export interface ArgentWallet {
  account: Account;
  accountContract: Contract;
  ownerPrivateKey: string;
  guardianPrivateKey?: string;
  guardianBackupPrivateKey?: string;
}

export const deployer = new Account(
  provider /* provider */,
  "0x347be35996a21f6bf0623e75dbce52baba918ad5ae8d83b6f416045ab22961a" /* address */,
  "0xbdd640fb06671ad11c80317fa3b1799d" /* private key */,
);

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
  await deployer.waitForTransaction(transaction_hash);
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
  await deployer.waitForTransaction(transaction_hash);
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

export async function upgradeAccount(
  accountToUpgrade: Account,
  argentAccountClassHash: string,
  calldata: RawCalldata = [],
): Promise<InvokeTransactionReceiptResponse> {
  const { transaction_hash: transferTxHash } = await accountToUpgrade.execute({
    contractAddress: accountToUpgrade.address,
    entrypoint: "upgrade",
    calldata: CallData.compile({ implementation: argentAccountClassHash, calldata }),
  });
  return await provider.waitForTransaction(transferTxHash);
}
