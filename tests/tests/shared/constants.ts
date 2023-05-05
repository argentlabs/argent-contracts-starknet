import { Account, Contract, Provider } from "starknet";
import { loadContract } from "./lib";

export const baseUrl = "http://127.0.0.1:5050";
export const provider = new Provider({ sequencer: { baseUrl } });
export const account = new Account(
  provider,
  "0x347be35996a21f6bf0623e75dbce52baba918ad5ae8d83b6f416045ab22961a",
  "0xbdd640fb06671ad11c80317fa3b1799d",
); // TODO Try replace with argent account at first

export const ethAddress = "0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7";
let ethContract: Contract;

export async function getEthContract() {
  if (ethContract) {
    return ethContract;
  }
  ethContract = await loadContract(ethAddress);
  return ethContract;
}
