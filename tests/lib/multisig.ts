import { Account, CallData, Contract, ec, GetTransactionReceiptResponse, hash } from "starknet";
import { deployer } from "./accounts";
import { loadContract } from "./contracts";
import { fundAccount } from "./devnet";
import { provider } from "./provider";
import { MultisigSigner, randomPrivateKey, randomPrivateKeys } from "./signers";

export interface MultisigWallet {
  account: Account;
  accountContract: Contract;
  privateKeys: string[];
  signers: bigint[]; // public keys
  receipt: GetTransactionReceiptResponse;
}

export async function deployMultisig(
  classHash: string,
  threshold: number,
  signersLength: number,
): Promise<MultisigWallet> {
  const privateKeys = randomPrivateKeys(signersLength);
  const signers = privateKeys.map(ec.starkCurve.getStarkKey).map(BigInt);
  const constructorCalldata = CallData.compile({ threshold, signers });
  const addressSalt = randomPrivateKey();

  const contractAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);
  await fundAccount(contractAddress);

  const deploymentSigner = new MultisigSigner(privateKeys.slice(0, 1));
  const account = new Account(provider, contractAddress, deploymentSigner, "1");
  account.signer = new MultisigSigner(privateKeys.slice(0, threshold));

  const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt });
  const receipt = await deployer.waitForTransaction(transaction_hash);

  const accountContract = await loadContract(account.address);
  return { account, accountContract, privateKeys, signers, receipt };
}
