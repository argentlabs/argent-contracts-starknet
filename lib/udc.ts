import { RawCalldata } from "starknet";
import { deployer, manager } from ".";

export const udcAddress = "0x041a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf";

export async function deployContractUDC(
  classHash: string,
  salt: string,
  constructorCalldata: RawCalldata,
): Promise<string> {
  const udcContract = await manager.loadContract(udcAddress);
  udcContract.connect(deployer);
  // deployContract uses the UDC
  // TODO There is an issue here, isn't there?
  const { transaction_hash } = await udcContract.deployContract(classHash, salt, 0, constructorCalldata);
  // Any: Ugly hack to get the contract address from the receipt
  const receipt: any = await deployer.getTransactionReceipt(transaction_hash);
  return receipt.contract_address;
}
