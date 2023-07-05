import { SequencerProvider } from "starknet";

// Polls quickly for a local network
export class FastProvider extends SequencerProvider {
  get isDevnet() {
    return this.baseUrl.startsWith("http://127.0.0.1:");
  }

  waitForTransaction(txHash: string, options = {}) {
    if (this.isDevnet) {
      return super.waitForTransaction(txHash, { retryInterval: 250, ...options });
    } else {
      return super.waitForTransaction(txHash, options);
    }
  }
}

export const provider = new FastProvider({ baseUrl: process.env.BASE_URL || "http://127.0.0.1:5050" });
