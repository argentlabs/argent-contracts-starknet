import { RawArgs, RpcProvider } from "starknet";
import { Constructor } from ".";

const dumpFolderPath = "./dump";
export const devnetBaseUrl = "http://127.0.0.1:5050";

export const WithDevnet = <T extends Constructor<RpcProvider>>(Base: T) =>
  class extends Base {
    get isDevnet() {
      return this.channel.nodeUrl.startsWith(devnetBaseUrl);
    }

    // Polls quickly for a local network
    waitForTransaction(transactionHash: string, options = {}) {
      const retryInterval = this.isDevnet ? 100 : 1000;
      return super.waitForTransaction(transactionHash, { retryInterval, ...options });
    }

    async mintEth(address: string, amount: number | bigint) {
      await this.handleJsonRpc("devnet_mint", { address, amount: Number(amount) });
    }

    async mintStrk(address: string, amount: number | bigint) {
      await this.handleJsonRpc("devnet_mint", { address, amount: Number(amount), unit: "FRI" });
    }

    async increaseTime(timeInSeconds: number | bigint) {
      await this.handleJsonRpc("devnet_increaseTime", { time: Number(timeInSeconds) });
    }

    async setTime(timeInSeconds: number | bigint) {
      await this.handleJsonRpc("devnet_setTime", { time: Number(timeInSeconds), generate_block: true });
    }

    async restart() {
      await this.handleJsonRpc("devnet_restart");
    }

    async dump() {
      await this.handleJsonRpc("devnet_dump", { path: dumpFolderPath });
    }

    async load() {
      await this.handleJsonRpc("devnet_load", { path: dumpFolderPath });
    }

    async handlePost(path: string, payload?: RawArgs) {
      const url = `${this.channel.nodeUrl}/${path}`;
      const headers = { "Content-Type": "application/json" };
      const response = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
      if (!response.ok) {
        throw new Error(`HTTP error! calling ${url} Status: ${response.status} Message: ${await response.text()}`);
      }
    }

    async handleJsonRpc(method: string, params: any = {}) {
      const body = {
        jsonrpc: "2.0",
        id: Date.now(),
        method,
        params,
      };

      const res = await fetch(`${this.channel.nodeUrl}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      const json = await res.json();

      if (json.error) {
        throw new Error(`RPC Error: ${json.error.message}`);
      }

      return json.result;
    }
  };
