import { assert } from "chai";
import { TransactionFinalityStatus, TransactionReceipt } from "starknet";
import { manager } from "./manager";

export async function ensureSuccess(
  transactionOrHash: { transaction_hash: string } | string,
): Promise<TransactionReceipt> {
  const transactionHash =
    typeof transactionOrHash === "string" ? transactionOrHash : transactionOrHash.transaction_hash;
  const tx = await manager.waitForTx(transactionHash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  assert(tx.isSuccess(), `Transaction ${transactionHash} REVERTED`);
  return tx;
}

export async function ensureAccepted(
  transactionOrHash: { transaction_hash: string } | string,
): Promise<TransactionReceipt> {
  const transactionHash =
    typeof transactionOrHash === "string" ? transactionOrHash : transactionOrHash.transaction_hash;
  const receipt = await manager.waitForTx(transactionHash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  return receipt as TransactionReceipt;
}
