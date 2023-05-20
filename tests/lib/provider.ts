import { SequencerProvider } from "starknet";

// Polls quickly for a local network
class FastProvider extends SequencerProvider {
  waitForTransaction(txHash: string, options = {}) {
    return super.waitForTransaction(txHash, { retryInterval: 250, ...options });
  }
}

export const baseUrl = "http://127.0.0.1:5050";
export const provider = new FastProvider({ baseUrl });
