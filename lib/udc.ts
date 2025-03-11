import { RawCalldata, UniversalDeployerContractPayload } from "starknet";
import { deployer } from ".";

export const udcAddress = "0x41a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf";

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
  const { contract_address, transaction_hash } = await deployer.deployContract(udcPayload);
  await deployer.waitForTransaction(transaction_hash);
  return { contractAddress: contract_address, transactionHash: transaction_hash };
}