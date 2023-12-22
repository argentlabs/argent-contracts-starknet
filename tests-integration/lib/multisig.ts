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
  selfDeploymentIndexes?: number[];
};

export async function deployMultisig(params: DeployMultisigParams): Promise<MultisigWallet> {
  const finalParams = {
    ...params,
    classHash: params.classHash ?? (await declareContract("ArgentMultisig")),
    salt: params.salt ?? num.toHex(randomKeyPair().privateKey),
    useTxV3: params.useTxV3 ?? false,
    selfDeploy: params.selfDeploy ?? false,
    selfDeploymentIndexes: params.selfDeploymentIndexes ?? [0],
  };

  if (params.selfDeploymentIndexes && !finalParams.selfDeploy) {
    throw new Error("selfDeploymentIndexes can only be used with selfDeploy");
  }

  const keys = sortedKeyPairs(finalParams.signersLength);
  const signers = keysToSigners(keys);
  const constructorCalldata = CallData.compile({ threshold: finalParams.threshold, signers });

  const accountAddress = hash.calculateContractAddressFromHash(
    finalParams.salt,
    finalParams.classHash,
    constructorCalldata,
    0 /* deployerAddress */,
  );

  const calls: Call[] = [];
  let fundingCall: Call | null = null;
  if (finalParams.useTxV3) {
    fundingCall = await fundAccountCall(accountAddress, finalParams.fundingAmount ?? 1e16, "STRK"); // 0.01 STRK
  } else {
    fundingCall = await fundAccountCall(accountAddress, finalParams.fundingAmount ?? 1e15, "ETH"); // 0.001 ETH
  }
  if (fundingCall) {
    calls.push(fundingCall);
  }

  const defaultTxVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;

  let transactionHash;
  if (finalParams.selfDeploy) {
    const response = await deployer.execute(calls);
    await provider.waitForTransaction(response.transaction_hash);

    const selfDeploymentSigner = new MultisigSigner(
      keys.filter((_, i) => finalParams.selfDeploymentIndexes.includes(i)),
    );
    const account = new Account(provider, accountAddress, selfDeploymentSigner, "1", defaultTxVersion);

    const { transaction_hash } = await account.deploySelf({
      classHash: finalParams.classHash,
      constructorCalldata,
      addressSalt: finalParams.salt,
    });
    transactionHash = transaction_hash;
  } else {
    calls.push(
      ...deployer.buildUDCContractPayload({
        classHash: finalParams.classHash,
        salt: finalParams.salt,
        constructorCalldata,
        unique: false,
      }),
    );
    const { transaction_hash } = await deployer.execute(calls);
    transactionHash = transaction_hash;
  }

  const receipt = await provider.waitForTransaction(transactionHash);
  const account = new Account(
    provider,
    accountAddress,
    new MultisigSigner(keys.slice(0, finalParams.threshold)),
    "1",
    defaultTxVersion,
  );
  const accountContract = await loadContract(account.address);
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
