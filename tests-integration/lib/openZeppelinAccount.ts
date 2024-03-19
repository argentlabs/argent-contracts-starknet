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

export async function deployOzAccount(params: DeployOzAccountParams): Promise<DeployOzAccountResult> {
  const classHash = await declareContract("OzAccount");
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
  const calls: Call[] = [];
  let fundingCall: Call | null = null;
  if (finalParams.useTxV3) {
    fundingCall = await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e16, "STRK"); // 0.01 STRK
  } else {
    fundingCall = await fundAccountCall(contractAddress, finalParams.fundingAmount ?? 1e18, "ETH"); // 1 ETH
  }
  if (fundingCall) {
    calls.push(fundingCall);
  }

  const defaultTxVersion = finalParams.useTxV3 ? RPC.ETransactionVersion.V3 : RPC.ETransactionVersion.V2;
  const account = new Account(provider, contractAddress, finalParams.owner, "1", defaultTxVersion);
  account.signer = new LegacyMultisigSigner([finalParams.owner]);

  if (calls.length > 0) {
    const response = await deployer.execute(calls);
    await provider.waitForTransaction(response.transaction_hash);
  }
  const { transaction_hash: deployTxHash } = await account.deploySelf({
    classHash: classHash,
    constructorCalldata,
    addressSalt: finalParams.salt,
  });

  await provider.waitForTransaction(deployTxHash);
  const accountContract = await loadContract(account.address);
  accountContract.connect(account);

  return { ...finalParams, account, accountContract, deployTxHash };
}
