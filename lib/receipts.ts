import { assert } from "chai";
import { GetTransactionReceiptResponse, RpcProvider, TransactionFinalityStatus, TransactionReceipt } from "starknet";
import { Constructor } from ".";

const successStates = [TransactionFinalityStatus.ACCEPTED_ON_L1, TransactionFinalityStatus.ACCEPTED_ON_L2];

export const WithReceipts = <T extends Constructor<RpcProvider>>(Base: T) =>
  class extends Base {
    async waitForTx(
      transactionOrHash: { transaction_hash: string } | string,
      options = {},
    ): Promise<GetTransactionReceiptResponse> {
      const transactionHash =
        typeof transactionOrHash === "string" ? transactionOrHash : transactionOrHash.transaction_hash;
      return this.waitForTransaction(transactionHash, { ...options });
    }

    async ensureSuccess(execute: () => Promise<{ transaction_hash: string }>): Promise<TransactionReceipt> {
      const executionResult = await execute();
      if (!("transaction_hash" in executionResult)) {
        throw new Error(`No transaction hash found on ${JSON.stringify(executionResult)}`);
      }
      const transactionHash = executionResult["transaction_hash"];
      const tx = await this.waitForTx(transactionHash, {
        successStates,
      });
      assert(tx.isSuccess(), `Transaction ${transactionHash} REVERTED`);
      return tx;
    }

    async ensureAccepted(execute: () => Promise<{ transaction_hash: string }>): Promise<TransactionReceipt> {
      const executionResult = await execute();
      if (!("transaction_hash" in executionResult)) {
        throw new Error(`No transaction hash found on ${JSON.stringify(executionResult)}`);
      }
      const transactionHash = executionResult["transaction_hash"];
      const receipt = await this.waitForTx(transactionHash, {
        successStates,
      });
      return receipt as TransactionReceipt;
    }
  };
