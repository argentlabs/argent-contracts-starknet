import { GetTransactionReceiptResponse, RawArgs, RpcProvider } from "starknet";
import { Constructor } from ".";

export const dumpFolderPath = "./dump";
export const devnetBaseUrl = "http://127.0.0.1:5050";

export const WithDevnet = <T extends Constructor<RpcProvider>>(Base: T) =>
  class extends Base {
    get isDevnet() {
      return this.channel.nodeUrl.startsWith(devnetBaseUrl);
    }

    async waitForTx(
      transactionOrHash: { transaction_hash: string } | string,
      options = {},
    ): Promise<GetTransactionReceiptResponse> {
      const transactionHash =
        typeof transactionOrHash === "string" ? transactionOrHash : transactionOrHash.transaction_hash;
      const retryInterval = this.isDevnet ? 250 : 1000;
      return super.waitForTransaction(transactionHash, { retryInterval, ...options });
    }

    async mintEth(address: string, amount: number | bigint) {
      await this.handlePost("mint", { address, amount: Number(amount) });
    }

    async increaseTime(timeInSeconds: number | bigint) {
      await this.handlePost("increase_time", { time: Number(timeInSeconds) });
    }

    async setTime(timeInSeconds: number | bigint) {
      await this.handlePost("set_time", { time: Number(timeInSeconds), generate_block: true });
    }

    async restart() {
      await this.handlePost("restart");
    }

    async dump() {
      await this.handlePost("dump", { path: dumpFolderPath });
    }

    async load() {
      await this.handlePost("load", { path: dumpFolderPath });
    }

    async handlePost(path: string, payload?: RawArgs) {
      const url = `${this.channel.nodeUrl}/${path}`;
      const headers = { "Content-Type": "application/json" };
      const response = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
      if (!response.ok) {
        throw new Error(`HTTP error! calling ${url} Status: ${response.status} Message: ${await response.text()}`);
      }
    }
  };
