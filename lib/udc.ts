import { defaultDeployer, RawCalldata, UniversalDeployerContractPayload } from "starknet";
import { deployer } from ".";

export async function deployContractUDC(
  classHash: string,
  salt: string,
  constructorCalldata: RawCalldata,
): Promise<{ contractAddress: string; transactionHash: string }> {
  const udcPayload = {
    classHash,
    salt,
    unique: false,
    constructorCalldata,
  } as UniversalDeployerContractPayload;
  // deployContract uses the UDC
  const { addresses, calls } = await defaultDeployer.buildDeployerCall(udcPayload, deployer.address);
  const { transaction_hash } = await deployer.execute(calls);
  await deployer.waitForTransaction(transaction_hash);
  return { contractAddress: addresses[0], transactionHash: transaction_hash };
}
