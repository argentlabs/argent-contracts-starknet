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
  receipt: TransactionReceipt | string,
): Promise<SuccessfulTransactionReceiptResponse> {
  const transactionHash = typeof receipt === "string" ? receipt : receipt.transaction_hash;
  await manager.waitForTransaction(transactionHash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  return receipt as SuccessfulTransactionReceiptResponse;
}
