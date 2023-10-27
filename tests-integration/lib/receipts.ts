import {
  SuccessfulTransactionReceiptResponse,
  RevertedTransactionReceiptResponse,
  GetTransactionReceiptResponse,
} from "starknet";

export type AcceptedTransactionReceiptResponse =
  | SuccessfulTransactionReceiptResponse
  | RevertedTransactionReceiptResponse;

// this might eventually be solved in starknet.js https://github.com/starknet-io/starknet.js/issues/796
export function isAcceptedTransactionReceiptResponse(
  receipt: GetTransactionReceiptResponse,
): receipt is AcceptedTransactionReceiptResponse {
  return "transaction_hash" in receipt;
}

export function ensureAccepted(receipt: GetTransactionReceiptResponse): AcceptedTransactionReceiptResponse {
  if (!isAcceptedTransactionReceiptResponse(receipt)) {
    throw new Error(`Transaction was rejected: ${JSON.stringify(receipt)}`);
  }
  return receipt;
}
