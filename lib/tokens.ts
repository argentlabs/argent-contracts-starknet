import { Contract } from "starknet";
import { Manager } from "./manager";

export const ethAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7";
export const strkAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export class TokenManager {
  private ethCache?: Contract;
  private strkCache?: Contract;

  constructor(private manager: Manager) {}

  async feeTokenContract(): Promise<Contract> {
    return this.strkContract();
  }

  async strkContract(): Promise<Contract> {
    if (this.strkCache) {
      return this.strkCache;
    }
    this.strkCache = await this.manager.loadContract(strkAddress);
    return this.strkCache;
  }

  async strkBalance(accountAddress: string): Promise<bigint> {
    const strkContract = await this.strkContract();
    return await strkContract.balanceOf(accountAddress);
  }
}
