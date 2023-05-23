import { expect } from "chai";
import { Account, CallData, Contract, InvokeTransactionReceiptResponse, RawCalldata, ec, encode, hash } from "starknet";
import { loadContract } from "./contracts";
import { fundAccount } from "./devnet";
import { provider } from "./provider";
import { ArgentSigner } from "./signers";

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

export function randomPrivateKey(): string {
  return "0x" + encode.buf2hex(ec.starkCurve.utils.randomPrivateKey());
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

  const salt = randomPrivateKey();
  const contractAddress = hash.calculateContractAddressFromHash(salt, proxyClassHash, constructorCalldata, 0);

  const account = new Account(provider, contractAddress, ownerPrivateKey);
  account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);

  await fundAccount(account.address);
  const { transaction_hash } = await account.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: salt,
  });
  await deployer.waitForTransaction(transaction_hash);
  const accountContract = await loadContract(account.address);
  return { account, accountContract, ownerPrivateKey, guardianPrivateKey };
}

async function deployAccountInner(
  argentAccountClassHash: string,
  ownerPrivateKey: string,
  guardianPrivateKey?: string,
  salt: string = randomPrivateKey(),
): Promise<Account> {
  const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

  const guardianPublicKey = guardianPrivateKey ? ec.starkCurve.getStarkKey(guardianPrivateKey) : "0";

  const constructorCalldata = CallData.compile({ owner: ownerPublicKey, guardian: guardianPublicKey });

  const contractAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress);
  const account = new Account(provider, contractAddress, ownerPrivateKey, "1");
  if (guardianPrivateKey) {
    account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
  }

  const { transaction_hash } = await account.deploySelf({
    classHash: argentAccountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await deployer.waitForTransaction(transaction_hash);
  return account;
}

export async function deployAccount(argentAccountClassHash: string): Promise<ArgentWallet> {
  const ownerPrivateKey = randomPrivateKey();
  const guardianPrivateKey = randomPrivateKey();
  const account = await deployAccountInner(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, ownerPrivateKey, guardianPrivateKey };
}

export async function deployAccountWithoutGuardian(
  argentAccountClassHash: string,
  ownerPrivateKey: string = randomPrivateKey(),
  salt: string = randomPrivateKey(),
): Promise<ArgentWallet> {
  const account = await deployAccountInner(argentAccountClassHash, ownerPrivateKey, salt);
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

export enum EscapeStatus {
  None,
  NotReady,
  Ready,
  Expired,
}

export async function getEscapeStatus(accountContract: Contract): Promise<EscapeStatus> {
  // StarknetJs parsing is broken so we do it manually
  const result = (await accountContract.call("get_escape_and_status", undefined, { parseResponse: false })) as string[];
  expect(result.length).to.equal(4);
  const status = Number(result[3]);
  expect(status).to.be.lessThan(4, `Unknown status ${status}`);
  return status;
}
