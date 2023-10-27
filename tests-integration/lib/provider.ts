import { RpcProvider, SequencerProvider } from "starknet";
import dotenv from "dotenv";
dotenv.config();

const devnetBaseUrl = "http://127.0.0.1:5050";

// Polls quickly for a local network
export class FastProvider extends SequencerProvider {
  get isDevnet() {
    return this.baseUrl.startsWith(devnetBaseUrl);
  }

  waitForTransaction(txHash: string, options = {}) {
    const retryInterval = this.isDevnet ? 250 : 1000;
    return super.waitForTransaction(txHash, { retryInterval, ...options });
  }
}

export const provider = new FastProvider({ baseUrl: process.env.BASE_URL || devnetBaseUrl });

export class FastRpcProvider extends RpcProvider {
  get isDevnet() {
    return this.nodeUrl.startsWith(devnetBaseUrl);
  }

  waitForTransaction(txHash: string, options = {}) {
    const retryInterval = this.isDevnet ? 250 : 1000;
    return super.waitForTransaction(txHash, { retryInterval, ...options });
  }
}

export const rpcProvider = new FastRpcProvider({ nodeUrl: process.env.RPC_URL || `${devnetBaseUrl}/rpc` });
console.log("Provider sequencer:", provider.baseUrl);
console.log("Provider rpc:", rpcProvider.nodeUrl);
