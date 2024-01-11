import { loadContract, deployer, provider } from ".";
import { CallData, InvokeTransactionReceiptResponse, RawCalldata } from "starknet";

export const udcAddress = "0x041a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf";

export async function deployContractUDC(classHash: string, salt: string, calldata: RawCalldata) {
  const unique = 0n; //false

  const udcContract = await loadContract(udcAddress);

  udcContract.connect(deployer);

  const deployCall = udcContract.populate("deployContract", CallData.compile([classHash, salt, unique, calldata]));
  const { transaction_hash } = await udcContract.deployContract(deployCall.calldata);

  const transaction_response = (await provider.waitForTransaction(
    transaction_hash,
  )) as InvokeTransactionReceiptResponse;

  return transaction_response.events?.[0].from_address;
}
