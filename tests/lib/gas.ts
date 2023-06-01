import { ExecutionResources, InvokeFunctionResponse, num, TransactionTraceResponse } from "starknet";
import { provider } from "./provider";

export async function profileGasUsage({ transaction_hash: txHash }: InvokeFunctionResponse) {
  const trace: TransactionTraceResponse = await provider.getTransactionTrace(txHash);
  const receipt = await provider.waitForTransaction(txHash);
  const actualFee = num.hexToDecimalString(receipt.actual_fee as string) as unknown as number;

  const executionResourcesByPhase: ExecutionResources[] = [
    trace.validate_invocation!.execution_resources!,
    trace.function_invocation!.execution_resources!,
    trace.fee_transfer_invocation!.execution_resources!,
  ];

  const allExecutionResources: ExecutionResources = executionResourcesByPhase.reduce(
    (a: ExecutionResources, b: ExecutionResources) => {
      const keys = [
        ...new Set(Object.keys(a.builtin_instance_counter).concat(Object.keys(b.builtin_instance_counter))),
      ];
      const combinedBuiltinCounterUnsafe = keys.reduce((acc, key: string) => {
        const aValue = (a.builtin_instance_counter as any)[key] ?? 0;
        const bValue = (b.builtin_instance_counter as any)[key] ?? 0;
        (acc as any)[key] = aValue + bValue;
        return acc;
      }, {});

      const combinedBuiltinCounter = (
        { ...a, builtin_instance_counter: combinedBuiltinCounterUnsafe } as ExecutionResources
      ).builtin_instance_counter;

      return {
        n_steps: a.n_steps + b.n_steps,
        n_memory_holes: a.n_memory_holes + b.n_memory_holes,
        builtin_instance_counter: combinedBuiltinCounter,
      };
    },
  );

  const blockNumber = (receipt as any)["block_number"];
  const blockInfo = await provider.getBlock(blockNumber);
  const stateUpdate = await provider.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const gasPrice = num.hexToDecimalString(blockInfo.gas_price as string) as unknown as number;
  const gasUsed = actualFee / gasPrice;

  // from https://docs.starknet.io/documentation/architecture_and_concepts/Fees/fee-mechanism/
  const gasWeights: { [categoryName: string]: number } = {
    n_steps: 0.01,
    pedersen_builtin: 0.32,
    range_check_builtin: 0.16,
    ec_op_builtin: 10.24,
    bitwise_builtin: 0.64,
    ecdsa_builtin: 20.48,
    output_builtin: 9999999999999, // Undefined in https://docs.starknet.io/documentation/architecture_and_concepts/Fees/fee-mechanism/
  };

  const executionResourcesFlat: { [categoryName: string]: number } = {
    ...allExecutionResources.builtin_instance_counter,
    n_steps: allExecutionResources.n_steps,
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
  const l1CalldataGas = gasUsed - computationGas;
  const gasUsage = {
    actualFee,
    gasUsed,
    l1CalldataGas,
    computationGas,
    maxComputationCategory,
    gasPerComputationCategory,
    executionResources: executionResourcesFlat,
    n_memory_holes: allExecutionResources.n_memory_holes,
    gasPrice,
    storageDiffs,
  };
  console.log(JSON.stringify(gasUsage));
  return receipt;
}
