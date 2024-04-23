import { Contract, RpcProvider, num } from "starknet";
import { Constructor, loadContract } from ".";

export const ethAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7";
export const strkAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export const WithTokens = <T extends Constructor<RpcProvider>>(Base: T) =>
  class extends Base {
    private ethContract?: Contract;
    private strkContract?: Contract;

    async getFeeTokenContract(useTxV3: boolean): Promise<Contract> {
      return useTxV3 ? this.getStrkContract() : this.getEthContract();
    }

    async getEthContract(): Promise<Contract> {
      if (this.ethContract) {
        return this.ethContract;
      }
      const ethProxy = await loadContract(ethAddress);
      if (ethProxy.abi.some((entry) => entry.name == "implementation")) {
        const { address } = await ethProxy.implementation();
        const { abi } = await loadContract(num.toHex(address));
        this.ethContract = new Contract(abi, ethAddress, ethProxy.providerOrAccount);
      } else {
        this.ethContract = ethProxy;
      }
      return this.ethContract;
    }

    async getStrkContract(): Promise<Contract> {
      if (this.strkContract) {
        return this.strkContract;
      }
      this.strkContract = await loadContract(strkAddress);
      return this.strkContract;
    }

    async getEthBalance(accountAddress: string): Promise<bigint> {
      const ethContract = await this.getEthContract();
      return await ethContract.balanceOf(accountAddress);
    }

    async getStrkBalance(accountAddress: string): Promise<bigint> {
      const strkContract = await this.getStrkContract();
      return await strkContract.balanceOf(accountAddress);
    }
  };
