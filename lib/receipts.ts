import { assert } from "chai";
import { GetTransactionReceiptResponse, RPC, TransactionExecutionStatus, TransactionFinalityStatus } from "starknet";
import { manager } from "./manager";

export async function ensureSuccess(receipt: GetTransactionReceiptResponse): Promise<RPC.Receipt> {
  const tx = await manager.waitForTransaction(receipt.transaction_hash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  assert(
    tx.execution_status == TransactionExecutionStatus.SUCCEEDED,
    `Transaction ${receipt.transaction_hash} REVERTED`,
  );
  return receipt as RPC.Receipt;
}

export async function ensureAccepted(receipt: GetTransactionReceiptResponse): Promise<RPC.Receipt> {
  await manager.waitForTransaction(receipt.transaction_hash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  return receipt as RPC.Receipt;
}
