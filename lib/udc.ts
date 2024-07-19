import { RawCalldata, UniversalDeployerContractPayload } from "starknet";
import { deployer, manager } from ".";

export const udcAddress = "0x041a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf";

export async function deployContractUDC(
  classHash: string,
  salt: string,
  constructorCalldata: RawCalldata,
): Promise<string> {
  const udcContract = await manager.loadContract(udcAddress);
  const udcPayload = {
    classHash,
    salt,
    unique: false,
    constructorCalldata,
  } as UniversalDeployerContractPayload;
  udcContract.connect(deployer);
  // deployContract uses the UDC
  const { contract_address, transaction_hash } = await deployer.deployContract(udcPayload);
  await deployer.waitForTransaction(transaction_hash);
  return contract_address;
}
