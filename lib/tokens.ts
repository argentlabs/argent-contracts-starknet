import { Contract, num } from "starknet";
import { WithContracts } from "./contracts";

export const ethAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7";
export const strkAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export const WithTokens = <T extends ReturnType<typeof WithContracts>>(Base: T) =>
  class extends Base {
    private ethCache?: Contract;
    private strkCache?: Contract;

    async feeTokenContract(useTxV3: boolean): Promise<Contract> {
      return useTxV3 ? this.strkContract() : this.ethContract();
    }

    async ethContract(): Promise<Contract> {
      if (this.ethCache) {
        return this.ethCache;
      }
      const ethProxy = await this.loadContract(ethAddress);
      if (ethProxy.abi.some((entry) => entry.name == "implementation")) {
        const { address } = await ethProxy.implementation();
        const { abi } = await this.loadContract(num.toHex(address));
        this.ethCache = new Contract(abi, ethAddress, ethProxy.providerOrAccount);
      } else {
        this.ethCache = ethProxy;
      }
      return this.ethCache;
    }

    async strkContract(): Promise<Contract> {
      if (this.strkCache) {
        return this.strkCache;
      }
      this.strkCache = await this.loadContract(strkAddress);
      return this.strkCache;
    }

    async ethBalance(accountAddress: string): Promise<bigint> {
      const ethContract = await this.ethContract();
      return await ethContract.balanceOf(accountAddress);
    }

    async strkBalance(accountAddress: string): Promise<bigint> {
      const strkContract = await this.strkContract();
      return await strkContract.balanceOf(accountAddress);
    }
  };
