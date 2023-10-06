import { loadContract } from "./contracts";
import { deployer } from "./accounts";
import { provider } from "./provider";
import { CallData, InvokeTransactionReceiptResponse } from "starknet";

export const udcAddress = "0x041a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf";

export async function deployContractUDC(classHash: string, salt: string, ownerPubKey: bigint, guardianPubKey: bigint) {
  const unique = 0n; //false

  const udcContract = await loadContract(udcAddress);

  udcContract.connect(deployer);

  const deployCall = udcContract.populate(
    "deployContract",
    CallData.compile([classHash, salt, unique, [ownerPubKey, guardianPubKey]]),
  );
  const { transaction_hash } = await udcContract.deployContract(deployCall.calldata);

  console.log("Transaction hash:", transaction_hash);

  let transaction_response = (await provider.waitForTransaction(transaction_hash)) as InvokeTransactionReceiptResponse;

  return transaction_response.events?.[0].from_address;
}
