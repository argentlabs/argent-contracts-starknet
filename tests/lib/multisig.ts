import { Account, CallData, Contract, GetTransactionReceiptResponse, hash } from "starknet";
import { deployer } from "./accounts";
import { loadContract } from "./contracts";
import { fundAccount } from "./devnet";
import { provider } from "./provider";
import { KeyPair, MultisigSigner, randomKeyPairs, randomPrivateKey } from "./signers";

export interface MultisigWallet {
  account: Account;
  accountContract: Contract;
  keys: KeyPair[];
  signers: bigint[]; // public keys
  receipt: GetTransactionReceiptResponse;
}

export async function deployMultisig(
  classHash: string,
  threshold: number,
  signersLength: number,
): Promise<MultisigWallet> {
  const keys = sortedKeyPairs(signersLength);

  const signers = keysToSigners(keys);
  const constructorCalldata = CallData.compile({ threshold, signers });
  const addressSalt = randomPrivateKey();

  const contractAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);
  await fundAccount(contractAddress);

  const deploymentSigner = new MultisigSigner([keys[0]]);
  const account = new Account(provider, contractAddress, deploymentSigner, "1");
  account.signer = new MultisigSigner(keys.slice(0, threshold));

  const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt });
  const receipt = await deployer.waitForTransaction(transaction_hash);

  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, keys, signers, receipt };
}

const sortedKeyPairs = (length: number) => randomKeyPairs(length).sort((a, b) => (a.publicKey < b.publicKey ? -1 : 1));

export const keysToSigners = (keys: KeyPair[]) => keys.map(({ publicKey }) => publicKey).map(BigInt);
