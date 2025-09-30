import { Contract } from "starknet";
import { Manager } from "./manager";

export const strkAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export class TokenManager {
  private strkCache?: Contract;

  constructor(private manager: Manager) {}

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
