import { GetTransactionReceiptResponse, RPC, TransactionExecutionStatus, TransactionFinalityStatus } from "starknet";
import { provider } from "./provider";

export async function ensureSuccess(receipt: GetTransactionReceiptResponse): Promise<RPC.Receipt> {
  await provider.waitForTransaction(receipt.transaction_hash, {
    successStates: [TransactionExecutionStatus.SUCCEEDED],
  });
  return receipt as RPC.Receipt;
}

export async function ensureAccepted(receipt: GetTransactionReceiptResponse): Promise<RPC.Receipt> {
  await provider.waitForTransaction(receipt.transaction_hash, {
    successStates: [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2],
  });
  return receipt as RPC.Receipt;
}
