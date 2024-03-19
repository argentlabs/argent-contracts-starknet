import { Account, CallData, RPC, hash, num, Call } from "starknet";
import { loadContract, declareContract, ContractWithClassHash } from "./contracts";
import { provider } from "./provider";
import { randomStarknetKeyPair } from "./signers/signers";
import { LegacyStarknetKeyPair, LegacyMultisigSigner } from "./signers/legacy";
import { fundAccountCall, deployer } from "./accounts";

export type DeployOzAccountParams = {
  useTxV3?: boolean;
  owner?: LegacyStarknetKeyPair;
  salt?: string;
  fundingAmount?: number | bigint;
};

export type DeployOzAccountResult = {
  account: Account;
  accountContract: ContractWithClassHash;
  deployTxHash: string;
  useTxV3: boolean;
  owner: LegacyStarknetKeyPair;
  salt: string;
};

export async function deployOpenZeppelinAccount(params: DeployOzAccountParams): Promise<DeployOzAccountResult> {
  const classHash = await declareContract("Account");
  const finalParams = {
    ...params,
    salt: params.salt ?? num.toHex(randomStarknetKeyPair().privateKey),
    owner: params.owner ?? new LegacyStarknetKeyPair(),
    useTxV3: params.useTxV3 ?? false,
  };

  const constructorCalldata = CallData.compile({
    owner: finalParams.owner.publicKey,
  });

  const contractAddress = hash.calculateContractAddressFromHash(finalParams.salt, classHash, constructorCalldata, 0);

  const fundingCall = finalParams.useTxV3
    ? await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e18, "STRK")
    : await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e16, "ETH");
  const response = await deployer.execute([fundingCall!!]);
  await provider.waitForTransaction(response.transaction_hash);

  const defaultTxVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;
  const signer = new LegacyMultisigSigner([finalParams.owner]);
  const account = new Account(provider, contractAddress, signer, "1", defaultTxVersion);

  const { transaction_hash: deployTxHash } = await account.deploySelf({
    classHash,
    constructorCalldata,
    addressSalt: finalParams.salt,
  });

  await provider.waitForTransaction(deployTxHash);
  const accountContract = await loadContract(account.address, classHash);
  accountContract.connect(account);

  return { ...finalParams, account, accountContract, deployTxHash };
}
