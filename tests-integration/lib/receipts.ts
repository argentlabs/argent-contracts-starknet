import { GetTransactionReceiptResponse, RPC } from "starknet";

export type AcceptedTransactionReceiptResponse = GetTransactionReceiptResponse & { transaction_hash: string };

// this might eventually be solved in starknet.js https://github.com/starknet-io/starknet.js/issues/796
export function isAcceptedTransactionReceiptResponse(
  receipt: GetTransactionReceiptResponse,
): receipt is AcceptedTransactionReceiptResponse {
  return "transaction_hash" in receipt;
}

export function isIncludedTransactionReceiptResponse(receipt: GetTransactionReceiptResponse): receipt is RPC.Receipt {
  return receipt.finality_status == 'ACCEPTED_ON_L2';
}

export function ensureAccepted(receipt: GetTransactionReceiptResponse): AcceptedTransactionReceiptResponse {
  if (!isAcceptedTransactionReceiptResponse(receipt)) {
    throw new Error(`Transaction was rejected: ${JSON.stringify(receipt)}`);
  }
  return receipt;
}

export function ensureIncluded(receipt: GetTransactionReceiptResponse): RPC.Receipt {
  const acceptedReceipt = ensureAccepted(receipt);
  if (!isIncludedTransactionReceiptResponse(acceptedReceipt)) {
    throw new Error(`Transaction was not included in a block: ${JSON.stringify(receipt)}`);
  }
  return acceptedReceipt;
}
