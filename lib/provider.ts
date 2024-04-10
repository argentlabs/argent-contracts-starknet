import dotenv from "dotenv";
import { RpcProvider } from "starknet";
import { clearCache } from "./contracts";
import { restart } from "./devnet";

dotenv.config({ override: true });

const devnetBaseUrl = "http://127.0.0.1:5050";

// Polls quickly for a local network
export class FastRpcProvider extends RpcProvider {
  get isDevnet() {
    return this.channel.nodeUrl.startsWith(devnetBaseUrl);
  }

  waitForTransaction(txHash: string, options = {}) {
    const retryInterval = this.isDevnet ? 250 : 1000;
    return super.waitForTransaction(txHash, { retryInterval, ...options });
  }
}

export const provider = new FastRpcProvider({ nodeUrl: process.env.RPC_URL || `${devnetBaseUrl}` });
console.log("Provider:", provider.channel.nodeUrl);

export const restartDevnet = async () => {
  if (provider.isDevnet) {
    await restart();
    clearCache();
  }
};
