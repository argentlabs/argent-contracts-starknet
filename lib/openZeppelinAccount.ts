import { Account, CallData, ETransactionVersion, hash, num } from "starknet";
import { deployer, fundAccountWithStrkCall } from "./accounts";
import { ContractWithClass } from "./contracts";
import { manager } from "./manager";
import { LegacyMultisigSigner, LegacyStarknetKeyPair } from "./signers/legacy";
import { randomStarknetKeyPair } from "./signers/signers";

type DeployOzAccountParams = {
  owner?: LegacyStarknetKeyPair;
  salt?: string;
  fundingAmount?: number | bigint;
};

type DeployOzAccountResult = {
  account: Account;
  accountContract: ContractWithClass;
  deployTxHash: string;
  owner: LegacyStarknetKeyPair;
  salt: string;
};

export async function deployOpenZeppelinAccount(params: DeployOzAccountParams): Promise<DeployOzAccountResult> {
  const classHash = await manager.declareLocalContract("AccountUpgradeable");
  const finalParams = {
    ...params,
    salt: params.salt ?? num.toHex(randomStarknetKeyPair().privateKey),
    owner: params.owner ?? new LegacyStarknetKeyPair(),
  };

  const constructorCalldata = CallData.compile({
    owner: finalParams.owner.publicKey,
  });

  const contractAddress = hash.calculateContractAddressFromHash(finalParams.salt, classHash, constructorCalldata, 0);

  const fundingCall = fundAccountWithStrkCall(contractAddress, finalParams.fundingAmount ?? 1e18);
  await manager.waitForTx(deployer.execute([fundingCall!]));

  const signer = new LegacyMultisigSigner([finalParams.owner]);
  const account = new Account({
    provider: manager,
    address: contractAddress,
    signer: signer,
    cairoVersion: "1",
    transactionVersion: ETransactionVersion.V3,
  });

  const { transaction_hash: deployTxHash } = await account.deploySelf({
    classHash,
    constructorCalldata,
    addressSalt: finalParams.salt,
  });

  await manager.waitForTx(deployTxHash);
  const accountContract = await manager.loadContract(account.address, classHash);
  accountContract.providerOrAccount = account;

  return { ...finalParams, account, accountContract, deployTxHash };
}
