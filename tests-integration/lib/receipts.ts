import { GetTransactionReceiptResponse, RPC, TransactionExecutionStatus } from "starknet";
import { provider } from "./provider";

export async function ensureAccepted(receipt: GetTransactionReceiptResponse): Promise<RPC.Receipt> {
  await provider.waitForTransaction(receipt.transaction_hash, {
    successStates: [TransactionExecutionStatus.SUCCEEDED],
  });
  return receipt as RPC.Receipt;
}
