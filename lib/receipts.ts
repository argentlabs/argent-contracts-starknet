import {
  GetTransactionReceiptResponse,
  RpcProvider,
  TransactionExecutionStatus,
  TransactionFinalityStatus,
  TransactionReceipt,
} from "starknet";
import { Constructor } from ".";

const successStates = [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2];

export const WithReceipts = <T extends Constructor<RpcProvider>>(Base: T) =>
  class extends Base {
    async waitForTx(
      execute: Promise<{ transaction_hash: string }> | { transaction_hash: string } | string,
      options = {},
    ): Promise<GetTransactionReceiptResponse> {
      let transactionHash: string;
      if (typeof execute === "string") {
        transactionHash = execute;
      } else {
        const executionResult = await execute;
        if (!("transaction_hash" in executionResult)) {
          throw new Error(`No transaction hash found on ${JSON.stringify(executionResult)}`);
        }
        transactionHash = executionResult["transaction_hash"];
      }

      return this.waitForTransaction(transactionHash, { ...options });
    }

    async ensureSuccess(
      execute: Promise<{ transaction_hash: string }> | { transaction_hash: string },
    ): Promise<TransactionReceipt> {
      const tx = await this.waitForTx(execute, {
        successStates: [TransactionExecutionStatus.SUCCEEDED],
      });
      return tx as TransactionReceipt;
    }

    async ensureAccepted(
      execute: Promise<{ transaction_hash: string }> | { transaction_hash: string },
    ): Promise<TransactionReceipt> {
      const receipt = await this.waitForTx(execute, {
        successStates,
      });
      return receipt as TransactionReceipt;
    }
  };
