import { InvokeFunctionResponse, num } from "starknet";
import { provider } from ".";

export async function profileGasUsage({ transaction_hash: transferTxHash }: InvokeFunctionResponse) {
  const receipt = await provider.waitForTransaction(transferTxHash);
  const actualFee = num.hexToDecimalString(receipt.actual_fee as string) as unknown as number;
  const executionResources = (receipt as any)["execution_resources"];
  const blockNumber = (receipt as any)["block_number"];
  const blockInfo = await provider.getBlock(blockNumber);
  const stateUpdate = await provider.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const gasPrice = num.hexToDecimalString(blockInfo.gas_price as string) as unknown as number;
  const gasUsed = actualFee / gasPrice;
  // TODO there are more built-ins
  // from https://docs.starknet.io/documentation/architecture_and_concepts/Fees/fee-mechanism/
  const gasWeights: { [categoryName: string]: number } = {
    n_steps: 0.01,
    pedersen_builtin: 0.32,
    range_check_builtin: 0.16,
    ec_op_builtin: 10.24,
  };

  const executionResourcesFlat: { [categoryName: string]: number } = {
    ...executionResources.builtin_instance_counter,
    n_steps: executionResources.n_steps,
  };
  const gasPerComputationCategory: { [categoryName: string]: number } = Object.entries(executionResourcesFlat)
    .filter(([resource]) => resource in gasWeights)
    .map(([resource, usage]) => [resource, Math.ceil(usage * gasWeights[resource])])
    .reduce((acc: { [categoryName: string]: number }, [resource, value]) => {
      acc[resource] = value as number;
      return acc;
    }, {});
  const maxComputationCategory: string = Object.keys(gasPerComputationCategory).reduce((a, b) => {
    return gasPerComputationCategory[a] > gasPerComputationCategory[b] ? a : b;
  });
  const computationGas = gasPerComputationCategory[maxComputationCategory];
  const l1Gas = gasUsed - computationGas;
  const gasUsage = {
    actualFee,
    gasUsed,
    l1Gas,
    computationGas,
    maxComputationCategory,
    gasPerComputationCategory,
    executionResources: executionResourcesFlat,
    n_memory_holes: executionResources.n_memory_holes,
    gasPrice,
    storageDiffs,
  };
  console.log(JSON.stringify(gasUsage));

  return receipt;
}
