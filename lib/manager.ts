import dotenv from "dotenv";
import { RpcProvider } from "starknet";
import { WithContracts } from "./contracts";
import { WithDevnet, devnetBaseUrl } from "./devnet";
import { WithReceipts } from "./receipts";
import { TokenManager } from "./tokens";

dotenv.config({ override: true });

export class Manager extends WithReceipts(WithContracts(WithDevnet(RpcProvider))) {
  tokens: TokenManager;

  constructor(nodeUrl: string) {
    super({ nodeUrl });
    this.tokens = new TokenManager(this);
  }
}
export const manager = new Manager(process.env.RPC_URL || `${devnetBaseUrl}`);

console.log("Provider:", manager.channel.nodeUrl);
