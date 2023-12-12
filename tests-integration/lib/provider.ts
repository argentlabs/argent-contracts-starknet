import { RpcProvider } from "starknet";
import dotenv from "dotenv";
import { restart } from "./devnet";
import { clearCache } from "./contracts";

dotenv.config();

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

let lastRestartTime = 0;

export const restartDevnet = async () => {
  if (provider.isDevnet) {
    lastRestartTime = Date.now();
    await restart();
    clearCache();
  }
};

// Unfortunate hack to restart devnet once in a while since otherwise the memory keeps increasing until it crashes
export const restartDevnetIfTooLong = async () => {
  if (!provider.isDevnet) return false;
  const restartInterval = 1000 * 60; // 1 minute
  if (Date.now() - lastRestartTime > restartInterval) {
    console.log("Restarting devnet...");
    await restartDevnet();
    return true;
  }
  return false;
};
