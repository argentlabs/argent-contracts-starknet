import { assert } from "chai";
import { TransactionFinalityStatus, TransactionReceipt } from "starknet";
import { manager } from "./manager";

export async function ensureSuccess(receiptOrHash: TransactionReceipt | string): Promise<TransactionReceipt> {
  const transactionHash = typeof receiptOrHash === "string" ? receiptOrHash : receiptOrHash.transaction_hash;
  const tx = await manager.waitForTransaction(transactionHash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  assert(tx.isSuccess(), `Transaction ${transactionHash} REVERTED`);
  return tx;
}

export async function ensureAccepted(receiptOrHash: TransactionReceipt | string): Promise<TransactionReceipt> {
  const transactionHash = typeof receiptOrHash === "string" ? receiptOrHash : receiptOrHash.transaction_hash;
  const receipt = await manager.waitForTransaction(transactionHash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  return receipt as TransactionReceipt;
}
