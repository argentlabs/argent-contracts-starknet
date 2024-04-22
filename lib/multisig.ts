import { Account, CallData, Contract, GetTransactionReceiptResponse, RPC, hash, num } from "starknet";
import {
  ArgentAccount,
  KeyPair,
  LegacyMultisigSigner,
  MultisigSigner,
  declareContract,
  deployer,
  fundAccount,
  fundAccountCall,
  loadContract,
  provider,
  randomLegacyMultisigKeyPairs,
  randomStarknetKeyPair,
  randomStarknetKeyPairs,
  sortByGuid,
} from ".";

export interface MultisigWallet {
  account: Account;
  accountContract: Contract;
  keys: KeyPair[];
  threshold: bigint;
  receipt: GetTransactionReceiptResponse;
}

export type DeployMultisigParams = {
  threshold: number;
  signersLength?: number;
  keys?: KeyPair[];
  useTxV3?: boolean;
  classHash?: string;
  salt?: string;
  fundingAmount?: number | bigint;
  selfDeploy?: boolean;
  selfDeploymentIndexes?: number[];
};

export async function deployMultisig(params: DeployMultisigParams): Promise<MultisigWallet> {
  const finalParams = {
    ...params,
    classHash: params.classHash ?? (await declareContract("ArgentMultisigAccount")),
    salt: params.salt ?? num.toHex(randomStarknetKeyPair().privateKey),
    useTxV3: params.useTxV3 ?? false,
    selfDeploy: params.selfDeploy ?? false,
    selfDeploymentIndexes: params.selfDeploymentIndexes ?? [0],
  };

  if (params.selfDeploymentIndexes && !finalParams.selfDeploy) {
    throw new Error("selfDeploymentIndexes can only be used with selfDeploy");
  }

  if (!params.keys && !finalParams.signersLength) {
    throw new Error("Fill in one of 'keys' or 'signersLength'");
  }
  const keys = params.keys ?? sortedKeyPairs(finalParams.signersLength!);
  const signers = keysToSigners(keys);
  const constructorCalldata = CallData.compile({ threshold: finalParams.threshold, signers });

  const { classHash, salt, selfDeploymentIndexes } = finalParams;
  const accountAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);

  const fundingCall = finalParams.useTxV3
    ? await fundAccountCall(accountAddress, finalParams.fundingAmount ?? 1e16, "STRK") // 0.01 STRK
    : await fundAccountCall(accountAddress, finalParams.fundingAmount ?? 1e15, "ETH"); // 0.001 ETH
  const calls = fundingCall ? [fundingCall] : [];

  const transactionVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;

  let transactionHash;
  if (finalParams.selfDeploy) {
    const response = await deployer.execute(calls);
    await provider.waitForTransaction(response.transaction_hash);

    const selfDeploymentSigner = new MultisigSigner(keys.filter((_, i) => selfDeploymentIndexes.includes(i)));
    const account = new Account(provider, accountAddress, selfDeploymentSigner, "1", transactionVersion);

    const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
    transactionHash = transaction_hash;
  } else {
    const udcCalls = deployer.buildUDCContractPayload({ classHash, salt, constructorCalldata, unique: false });
    const { transaction_hash } = await deployer.execute([...calls, ...udcCalls]);
    transactionHash = transaction_hash;
  }

  const receipt = await provider.waitForTransaction(transactionHash);
  const signer = new MultisigSigner(keys.slice(0, finalParams.threshold));
  const account = new ArgentAccount(provider, accountAddress, signer, "1", transactionVersion);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, keys, receipt, threshold: BigInt(finalParams.threshold) };
}

export async function deployMultisig1_3(
  params: Omit<DeployMultisigParams, "threshold" | "signersLength"> = {},
): Promise<MultisigWallet> {
  return deployMultisig({ ...params, threshold: 1, signersLength: 3 });
}

export async function deployMultisig1_1(
  params: Omit<DeployMultisigParams, "threshold" | "signersLength"> = {},
): Promise<MultisigWallet> {
  return deployMultisig({ ...params, threshold: 1, signersLength: 1 });
}

const sortedKeyPairs = (length: number) => sortByGuid(randomStarknetKeyPairs(length));

const keysToSigners = (keys: KeyPair[]) => keys.map(({ signer }) => signer);

export async function deployLegacyMultisig(classHash: string, threshold = 1) {
  const keys = randomLegacyMultisigKeyPairs(threshold);
  const signersPublicKeys = keys.map((key) => key.publicKey);
  const salt = num.toHex(randomStarknetKeyPair().privateKey);
  const constructorCalldata = CallData.compile({ threshold, signers: signersPublicKeys });
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15, "ETH"); // 0.001 ETH
  const deploySigner = new LegacyMultisigSigner([keys[0]]);
  const account = new Account(provider, contractAddress, deploySigner, "1");

  const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
  await provider.waitForTransaction(transaction_hash);

  const sortedKeys = keys.sort((n1, n2) => (n1.publicKey < n2.publicKey ? -1 : 1));
  const signers = new LegacyMultisigSigner(sortedKeys);
  account.signer = signers;
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);
  return { account, accountContract, deploySigner, signers };
}
