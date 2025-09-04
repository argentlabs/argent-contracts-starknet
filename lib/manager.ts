import dotenv from "dotenv";
import { RpcProvider, config, logger } from "starknet";
import { WithContracts } from "./contracts";
import { WithDevnet, devnetBaseUrl } from "./devnet";
import { WithReceipts } from "./receipts";
import { TokenManager } from "./tokens";
// This needs to be done here where we are actually using the env. Do not move this without testing
dotenv.config({ override: true });

export class Manager extends WithReceipts(WithContracts(WithDevnet(RpcProvider))) {
  tokens: TokenManager;

  constructor(nodeUrl: string) {
    super({ 
      nodeUrl,
      specVersion: '0.8.1' // Use RPC 0.8 by default for v7 compatibility
    });
    this.tokens = new TokenManager(this);
  }

  async getCurrentTimestamp(): Promise<number> {
    return (await this.getBlock("latest")).timestamp;
  }
}

// Check that process.env.RPC_URL is set and that it is allowed to be used
// Mostly done to prevent accidentally using the wrong network
if (process.env.RPC_URL && !process.argv.includes(`--allow-rpc-url-env`)) {
  console.log("When using RPC_URL, you must pass --allow-rpc-url-env");
  process.exit(1);
}

export const manager = new Manager(process.env.RPC_URL || `${devnetBaseUrl}`);

console.log("Provider:", manager.channel.nodeUrl);
console.log("RPC version:", await manager.channel.getSpecVersion());
