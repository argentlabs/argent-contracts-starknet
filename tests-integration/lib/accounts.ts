import { Account, CallData, Contract, GetTransactionReceiptResponse, RawCalldata, hash, num, uint256 } from "starknet";
import { getEthContract, loadContract } from "./contracts";
import { mintEth } from "./devnet";
import { provider } from "./provider";
import {
  ArgentSigner,
  KeyPair,
  LegacyArgentSigner,
  LegacyKeyPair,
  LegacyMultisigSigner,
  compiledSignerOption,
  randomKeyPair,
  signerOption,
  starknetSigner,
} from "./signers";

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
  if (provider.isDevnet) {
    const devnetAddress = "0x347be35996a21f6bf0623e75dbce52baba918ad5ae8d83b6f416045ab22961a";
    const devnetPrivateKey = "0xbdd640fb06671ad11c80317fa3b1799d";
    return new Account(provider, devnetAddress, devnetPrivateKey);
  }
  const address = process.env.ADDRESS;
  const privateKey = process.env.PRIVATE_KEY;
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
  const owner = new LegacyKeyPair();
  const guardian = new LegacyKeyPair();

  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey }),
  });

  const salt = num.toHex(randomKeyPair().privateKey);
  const contractAddress = hash.calculateContractAddressFromHash(salt, proxyClassHash, constructorCalldata, 0);

  const account = new Account(provider, contractAddress, owner);
  account.signer = new LegacyMultisigSigner([owner, guardian]);

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
  const some_guardian = signerOption(guardian?.publicKey);
  const constructorCalldata = CallData.compile({ owner: starknetSigner(owner.publicKey), guardian: some_guardian });
  const contractAddress = hash.calculateContractAddressFromHash(salt, argentAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15); // 0.001 ETH
  const account = new Account(provider, contractAddress, owner, "1");
  if (guardian) {
    account.signer = new ArgentSigner(owner, guardian);
  } else {
    account.signer = new ArgentSigner(owner);
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
  await wallet.accountContract.change_guardian_backup(compiledSignerOption(guardianBackup.publicKey));

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

export async function deployLegacyAccount(classHash: string) {
  const owner = new LegacyKeyPair();
  const guardian = new LegacyKeyPair();
  const salt = num.toHex(randomKeyPair().privateKey);
  const constructorCalldata = CallData.compile({ owner: owner.publicKey, guardian: guardian.publicKey });
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15); // 0.001 ETH
  const account = new Account(provider, contractAddress, owner, "1");
  account.signer = new LegacyArgentSigner(owner, guardian);

  const { transaction_hash } = await account.deploySelf({
    classHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);

  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, owner, guardian };
}

export async function fundAccount(recipient: string, amount: number | bigint) {
  if (provider.isDevnet) {
    await mintEth(recipient);
    return;
  }
  const ethContract = await getEthContract();
  ethContract.connect(deployer);

  const bn = uint256.bnToUint256(amount);
  return ethContract.invoke("transfer", CallData.compile([recipient, bn.low, bn.high]));
}
