import dotenv from "dotenv";
import { RpcProvider } from "starknet";
import { WithContracts } from "./contracts";
import { WithDevnet, devnetBaseUrl } from "./devnet";
import { TokenManager } from "./tokens";

dotenv.config({ override: true });

export class Manager extends WithContracts(WithDevnet(RpcProvider)) {
  tokens: TokenManager;

  constructor() {
    super({ nodeUrl: process.env.RPC_URL || `${devnetBaseUrl}` });
    this.tokens = new TokenManager(this);
  }
}

export const provider = new Manager();

console.log("Provider:", provider.channel.nodeUrl);
