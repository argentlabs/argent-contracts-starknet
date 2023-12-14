import {
  Account,
  CallData,
  Contract,
  GetTransactionReceiptResponse,
  RPC,
  RawCalldata,
  hash,
  num,
  uint256,
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

export const deployerData = (() => {
  if (provider.isDevnet) {
    const devnetAddress = "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691";
    const devnetPrivateKey = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
    return { provider: provider, address: devnetAddress, privateKey: devnetPrivateKey };
  }
  const address = process.env.ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;
  if (address && privateKey) {
    return { provider: provider, address: address, privateKey: privateKey };
  }
  throw new Error("Missing deployer address or private key, please set ADDRESS and PRIVATE_KEY env variables.");
})();

export const deployer = new Account(deployerData.provider, deployerData.address, deployerData.privateKey);
export const deployerV3 = new Account(
  deployerData.provider,
  deployerData.address,
  deployerData.privateKey,
  undefined,
  RPC.ETransactionVersion.V3,
);

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

  await fundAccount(account.address, 1e16); // 0.01 ETH

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
  await fundAccount(contractAddress, 1e16); // 0.01 ETH
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
): Promise<GetTransactionReceiptResponse> {
  const { transaction_hash: transferTxHash } = await accountToUpgrade.execute({
    contractAddress: accountToUpgrade.address,
    entrypoint: "upgrade",
    calldata: CallData.compile({ implementation: argentAccountClassHash, calldata }),
  });
  return await provider.waitForTransaction(transferTxHash);
}

export async function fundAccount(recipient: string, amount: number | bigint) {
  if (provider.isDevnet) {
    await mintEth(recipient, amount);
    return;
  }
  const ethContract = await getEthContract();
  ethContract.connect(deployer);

  const response = await ethContract.invoke("transfer", CallData.compile([recipient, uint256.bnToUint256(amount)]));
  await provider.waitForTransaction(response.transaction_hash);
}
