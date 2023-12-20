import { Account, CallData, Contract, GetTransactionReceiptResponse, hash, num, RPC, Call } from "starknet";
import {
  KeyPair,
  MultisigSigner,
  loadContract,
  provider,
  randomKeyPair,
  randomKeyPairs,
  fundAccountCall,
  declareContract,
  deployer,
} from ".";

export interface MultisigWallet {
  account: Account;
  accountContract: Contract;
  keys: KeyPair[];
  signers: bigint[]; // public keys
  threshold: bigint;
  receipt: GetTransactionReceiptResponse;
}
export type DeployMultisigParams = {
  threshold: number;
  signersLength: number;
  useTxV3?: boolean;
  classHash?: string;
  salt?: string;
  fundingAmount?: number | bigint;
  selfDeploy?: boolean;
  deploymentIndexes?: number[];
};

export async function deployMultisig(params: DeployMultisigParams): Promise<MultisigWallet> {
  const finalParams = {
    ...params,
    classHash: params.classHash ?? (await declareContract("ArgentMultisig")),
    salt: params.salt ?? num.toHex(randomKeyPair().privateKey),
    useTxV3: params.useTxV3 ?? false,
    selfDeploy: params.selfDeploy ?? false,
    deploymentIndexes: params.deploymentIndexes ?? [0],
  };

  const keys = sortedKeyPairs(finalParams.signersLength);
  const signers = keysToSigners(keys);
  const constructorCalldata = CallData.compile({ threshold: finalParams.threshold, signers });

  const contractAddress = hash.calculateContractAddressFromHash(
    finalParams.salt,
    finalParams.classHash,
    constructorCalldata,
    0 /* deployerAddress */,
  );

  const pendingCalls: Call[] = [];
  let fundingCall: Call | null = null;
  if (finalParams.useTxV3) {
    fundingCall = await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e16, "STRK"); // 0.01 STRK
  } else {
    fundingCall = await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e15, "ETH"); // 0.001 ETH
  }
  if (fundingCall) {
    pendingCalls.push(fundingCall);
  }

  const defaultTxVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;

  const deploymentSigner = new MultisigSigner(keys.filter((_, i) => finalParams.deploymentIndexes.includes(i)));
  const account = new Account(provider, contractAddress, deploymentSigner, "1", defaultTxVersion);

  let transactionHash;
  if (finalParams.selfDeploy) {
    const response = await deployer.execute(pendingCalls);
    await provider.waitForTransaction(response.transaction_hash);

    const { transaction_hash } = await account.deploySelf({
      classHash: finalParams.classHash,
      constructorCalldata,
      addressSalt: finalParams.salt,
    });
    transactionHash = transaction_hash;
  } else {
    pendingCalls.push(
      ...deployer.buildUDCContractPayload({
        classHash: finalParams.classHash,
        salt: finalParams.salt,
        constructorCalldata,
        unique: false,
      }),
    );
    const { transaction_hash } = await deployer.execute(pendingCalls);
    transactionHash = transaction_hash;
  }

  const receipt = await provider.waitForTransaction(transactionHash);

  const accountContract = await loadContract(account.address);
  account.signer = new MultisigSigner(keys.slice(0, finalParams.threshold));
  accountContract.connect(account);
  return { account, accountContract, keys, signers, receipt, threshold: BigInt(finalParams.threshold) };
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

const sortedKeyPairs = (length: number) => randomKeyPairs(length).sort((a, b) => (a.publicKey < b.publicKey ? -1 : 1));

export const keysToSigners = (keys: KeyPair[]) => keys.map(({ publicKey }) => publicKey).map(BigInt);
