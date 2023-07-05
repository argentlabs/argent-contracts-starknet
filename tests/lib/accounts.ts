import { expect } from "chai";
import {
  Account,
  CallData,
  Contract,
  InvokeTransactionReceiptResponse,
  RawCalldata,
  hash,
  num,
} from "starknet";
import { getEthContract, loadContract } from "./contracts";
import { mintEth } from "./devnet";
import { provider } from "./provider";
import { ArgentSigner, KeyPair, randomKeyPair } from "./signers";

export interface ArgentWallet {
  account: Account;
  accountContract: Contract;
  owner: KeyPair;
}

export interface ArgentWalletWithGuardian extends ArgentWallet {
  guardian: KeyPair;
}

export interface ArgentWalletWithGuardianAndBackup extends ArgentWalletWithGuardian {
  guardianBackup: KeyPair;
}

export const deployer = (() => {
  const address = process.env.ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;

  if (provider.isDevnet) {
    const devnetAddress = "0x347be35996a21f6bf0623e75dbce52baba918ad5ae8d83b6f416045ab22961a";
    const devnetPrivateKey = "0xbdd640fb06671ad11c80317fa3b1799d";
    return new Account(provider, address || devnetAddress, privateKey || devnetPrivateKey);
  }
  if (address && privateKey) {
    return new Account(provider, address, privateKey);
  }
  throw new Error("Missing deployer address or private key, please set ADDRESS and PRIVATE_KEY env variables.");
})();

console.log("Deployer:", deployer.address);

export async function deployOldAccount(
  proxyClassHash: string,
  oldArgentAccountClassHash: string,
): Promise<ArgentWalletWithGuardian> {
  const owner = randomKeyPair();
  const guardian = randomKeyPair();

  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey }),
  });

  const salt = num.toHex(randomKeyPair().privateKey);
  const contractAddress = hash.calculateContractAddressFromHash(salt, proxyClassHash, constructorCalldata, 0);

  const account = new Account(provider, contractAddress, owner);
  account.signer = new ArgentSigner(owner, guardian);

  await mintEth(account.address);
  const { transaction_hash } = await account.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian };
}

async function deployAccountInner(
  argentAccountClassHash: string,
  owner: KeyPair,
  guardian?: KeyPair,
  salt: string = num.toHex(randomKeyPair().privateKey),
): Promise<Account> {
  const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian?.publicKey ?? 0n });

  const contractAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e16);
  const account = new Account(provider, contractAddress, owner, "1");
  if (guardian) {
    account.signer = new ArgentSigner(owner, guardian);
  }

  const { transaction_hash } = await account.deploySelf({
    classHash: argentAccountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  return account;
}

export async function deployAccount(argentAccountClassHash: string): Promise<ArgentWalletWithGuardian> {
  const owner = randomKeyPair();
  const guardian = randomKeyPair();
  const account = await deployAccountInner(argentAccountClassHash, owner, guardian);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian };
}

export async function deployAccountWithoutGuardian(
  argentAccountClassHash: string,
  owner: KeyPair = randomKeyPair(),
  salt?: string,
): Promise<ArgentWallet> {
  const account = await deployAccountInner(argentAccountClassHash, owner, undefined, salt);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner };
}

export async function deployAccountWithGuardianBackup(
  argentAccountClassHash: string,
): Promise<ArgentWalletWithGuardianAndBackup> {
  const guardianBackup = randomKeyPair();

  const wallet = (await deployAccount(argentAccountClassHash)) as ArgentWalletWithGuardianAndBackup;
  await wallet.accountContract.change_guardian_backup(guardianBackup.publicKey);

  wallet.account.signer = new ArgentSigner(wallet.owner, guardianBackup);
  wallet.guardianBackup = guardianBackup;
  wallet.accountContract.connect(wallet.account);
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

export async function fundAccount(recipient: string, amount: number | bigint): Promise<void> {
  if (provider.isDevnet) {
    return await mintEth(recipient);
  }
  const ethContract = await getEthContract();
  ethContract.connect(deployer);

  await ethContract.invoke("transfer", CallData.compile([recipient, amount, 0]));
}

export enum EscapeStatus {
  None,
  NotReady,
  Ready,
  Expired,
}

export async function hasOngoingEscape(accountContract: Contract): Promise<boolean> {
  const escape = await accountContract.get_escape();
  return escape.escape_type != 0n && escape.ready_at != 0n && escape.new_signer != 0n;
}

export async function getEscapeStatus(accountContract: Contract): Promise<EscapeStatus> {
  // StarknetJs parsing is broken so we do it manually
  const result = (await accountContract.call("get_escape_and_status", undefined, { parseResponse: false })) as string[];
  expect(result.length).to.equal(4);
  const status = Number(result[3]);
  expect(status).to.be.lessThan(4, `Unknown status ${status}`);
  return status;
}
