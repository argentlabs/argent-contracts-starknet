import { SuccessfulTransactionReceiptResponse, RevertedTransactionReceiptResponse } from "starknet";

export type AcceptedTransactionReceiptResponse =
  | SuccessfulTransactionReceiptResponse
  | RevertedTransactionReceiptResponse;
