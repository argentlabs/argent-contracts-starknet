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

    async ensureSuccess(transactionOrHash: { transaction_hash: string } | string): Promise<TransactionReceipt> {
      const transactionHash =
        typeof transactionOrHash === "string" ? transactionOrHash : transactionOrHash.transaction_hash;
      const tx = await this.waitForTx(transactionHash, {
        successStates,
      });
      assert(tx.isSuccess(), `Transaction ${transactionHash} REVERTED`);
      return tx;
    }

    async ensureAccepted(transactionOrHash: { transaction_hash: string } | string): Promise<TransactionReceipt> {
      const transactionHash =
        typeof transactionOrHash === "string" ? transactionOrHash : transactionOrHash.transaction_hash;
      const receipt = await this.waitForTx(transactionHash, {
        successStates,
      });
      return receipt as TransactionReceipt;
    }
  };
