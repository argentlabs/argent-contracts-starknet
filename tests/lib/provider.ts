import { SequencerProvider, constants } from "starknet";

// Polls quickly for a local network
export class FastProvider extends SequencerProvider {
  waitForTransaction(txHash: string, options = {}) {
    if (this.baseUrl.startsWith("http://127.0.0.1:")) {
      return super.waitForTransaction(txHash, { retryInterval: 250, ...options });
    } else {
      return super.waitForTransaction(txHash, options);
    }
  }
}

// export const baseUrl = "http://127.0.0.1:5050";
export const baseUrl = constants.BaseUrl.SN_GOERLI;
// export const baseUrl = "https://external.integration.starknet.io/";

export const provider = new FastProvider({ baseUrl });
