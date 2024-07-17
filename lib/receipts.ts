import { assert } from "chai";
import { SuccessfulTransactionReceiptResponse, TransactionFinalityStatus, TransactionReceipt } from "starknet";
import { manager } from "./manager";

export async function ensureSuccess(receipt: TransactionReceipt): Promise<SuccessfulTransactionReceiptResponse> {
  const tx = await manager.waitForTransaction(receipt.transaction_hash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  assert(tx.isSuccess(), `Transaction ${receipt.transaction_hash} REVERTED`);
  return receipt as SuccessfulTransactionReceiptResponse;
}

export async function ensureAccepted(
  receiptOrHash: TransactionReceipt | string,
): Promise<SuccessfulTransactionReceiptResponse> {
  const transactionHash = typeof receiptOrHash === "string" ? receiptOrHash : receiptOrHash.transaction_hash;
  const receipt = await manager.waitForTransaction(transactionHash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  return receipt as SuccessfulTransactionReceiptResponse;
}
