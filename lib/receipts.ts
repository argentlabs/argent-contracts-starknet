import { expect } from "chai";
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
        transactionHash = executionResult["transaction_hash"];
      }
      return this.waitForTransaction(transactionHash, { ...options });
    }

    async ensureSuccess(
      execute: Promise<{ transaction_hash: string }> | { transaction_hash: string },
    ): Promise<TransactionReceipt> {
      // There is an annoying bug... if the tx isn't successful, the promise will never resolve (fails w timeout)
      const tx = await this.ensureAccepted(execute);
      expect(tx.execution_status, `Transaction failed: ${JSON.stringify(tx)}`).to.equal(
        TransactionExecutionStatus.SUCCEEDED,
      );
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
