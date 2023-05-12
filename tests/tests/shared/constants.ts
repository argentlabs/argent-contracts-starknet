import { Account, Contract, SequencerProvider } from "starknet";
import { loadContract } from "./lib";

// Polls quickly for a local network
class FastProvider extends SequencerProvider {
  waitForTransaction(txHash: string, options = {}) {
    return super.waitForTransaction(txHash, { retryInterval: 2000, ...options });
  }
}

const baseUrl = "http://127.0.0.1:5050";
const provider = new FastProvider({ baseUrl });

const deployerAccount = new Account(
  provider /* provider */,
  "0x347be35996a21f6bf0623e75dbce52baba918ad5ae8d83b6f416045ab22961a" /* address */,
  "0xbdd640fb06671ad11c80317fa3b1799d" /* private key */,
);

const ethAddress = "0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7";
let ethContract: Contract;

async function getEthContract() {
  if (ethContract) {
    return ethContract;
  }
  ethContract = await loadContract(ethAddress);
  return ethContract;
}

export { baseUrl, provider, deployerAccount, ethAddress, getEthContract };
