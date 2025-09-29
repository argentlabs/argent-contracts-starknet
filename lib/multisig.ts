import {
  Account,
  CallData,
  Contract,
  defaultDeployer,
  ETransactionVersion,
  GetTransactionReceiptResponse,
  hash,
  num,
} from "starknet";
import {
  ArgentAccount,
  deployer,
  fundAccount,
  fundAccountCall,
  KeyPair,
  LegacyMultisigKeyPair,
  LegacyMultisigSigner,
  manager,
  MultisigSigner,
  randomLegacyMultisigKeyPairs,
  randomStarknetKeyPair,
  randomStarknetKeyPairs,
  sortByGuid,
} from ".";

interface MultisigWallet {
  account: Account;
  accountContract: Contract;
  keys: KeyPair[];
  threshold: bigint;
  receipt: GetTransactionReceiptResponse;
}

type DeployMultisigParams = {
  threshold: number;
  signersLength?: number;
  keys?: KeyPair[];
  classHash?: string;
  salt?: string;
  fundingAmount?: number | bigint;
  selfDeploy?: boolean;
  selfDeploymentIndexes?: number[];
};

export async function deployMultisig(params: DeployMultisigParams): Promise<MultisigWallet> {
  const finalParams = {
    ...params,
    classHash: params.classHash ?? (await manager.declareLocalContract("ArgentMultisigAccount")),
    salt: params.salt ?? num.toHex(randomStarknetKeyPair().privateKey),
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

  const fundingCall = fundAccountCall(accountAddress, finalParams.fundingAmount ?? 5e18, "STRK"); // 5 STRK
  const calls = fundingCall ? [fundingCall] : [];

  let transactionHash;
  if (finalParams.selfDeploy) {
    const response = await deployer.execute(calls);
    await manager.waitForTx(response.transaction_hash);

    const selfDeploymentSigner = new MultisigSigner(keys.filter((_, i) => selfDeploymentIndexes.includes(i)));
    const account = new Account({
      provider: manager,
      address: accountAddress,
      signer: selfDeploymentSigner,
      cairoVersion: "1",
      transactionVersion: ETransactionVersion.V3,
    });

    const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
    transactionHash = transaction_hash;
  } else {
    const udcCalls = defaultDeployer.buildDeployerCall(
      { classHash, salt, constructorCalldata, unique: false },
      accountAddress,
    );
    const { transaction_hash } = await deployer.execute([...calls, ...udcCalls.calls]);
    transactionHash = transaction_hash;
  }

  const receipt = await manager.waitForTx(transactionHash);
  const signer = new MultisigSigner(keys.slice(0, finalParams.threshold));
  const account = new ArgentAccount({ provider: manager, address: accountAddress, signer });
  const accountContract = await manager.loadContract(account.address);
  accountContract.providerOrAccount = account;
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

interface LegacyMultisigWallet {
  account: Account;
  accountContract: Contract;
  keys: LegacyMultisigKeyPair[];
  deploySigner: LegacyMultisigSigner;
}

export async function deployLegacyMultisig(classHash: string, threshold = 1): Promise<LegacyMultisigWallet> {
  const keys = randomLegacyMultisigKeyPairs(threshold);
  const signersPublicKeys = keys.map((key) => key.publicKey);
  const salt = num.toHex(randomStarknetKeyPair().privateKey);
  const constructorCalldata = CallData.compile({ threshold, signers: signersPublicKeys });
  const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 5e18, "STRK"); // 5 STRK
  const deploySigner = new LegacyMultisigSigner([keys[0]]);
  const account = new Account({
    provider: manager,
    address: contractAddress,
    signer: deploySigner,
    cairoVersion: "1",
    transactionVersion: ETransactionVersion.V3,
  });

  const { transaction_hash } = await account.deploySelf({ classHash, constructorCalldata, addressSalt: salt });
  await manager.waitForTx(transaction_hash);

  account.signer = new LegacyMultisigSigner(keys);
  const accountContract = await manager.loadContract(account.address);
  accountContract.providerOrAccount = account;
  return { account, accountContract, deploySigner, keys };
}
