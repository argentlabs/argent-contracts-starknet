import { SequencerProvider } from "starknet";

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

console.log("Provider:", provider.baseUrl);
