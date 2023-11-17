import { add, maxBy, mergeWith, omit, sortBy, sum } from "lodash-es";
import { ExecutionResources, InvokeFunctionResponse, Sequencer } from "starknet";
import { provider } from "./provider";
import { AcceptedTransactionReceiptResponse, ensureAccepted } from "./receipts";

const ethUsd = 1800n;

export async function profileGasUsage({ transaction_hash: txHash }: InvokeFunctionResponse) {
  const trace: Sequencer.TransactionTraceResponse = await provider.getTransactionTrace(txHash);
  const receipt = ensureAccepted(await provider.waitForTransaction(txHash));
  const actualFee = BigInt(receipt.actual_fee as string);

  const executionResourcesByPhase: ExecutionResources[] = [
    trace.validate_invocation!.execution_resources!,
    trace.function_invocation!.execution_resources!,
    trace.fee_transfer_invocation!.execution_resources!,
  ];

  const allBuiltins = executionResourcesByPhase.map((resource) => resource.builtin_instance_counter);
  const executionResources: Record<string, number> = {
    n_steps: sum(executionResourcesByPhase.map((resource) => resource.n_steps)),
    n_memory_holes: sum(executionResourcesByPhase.map((resource) => resource.n_memory_holes)),
    ...mergeWith({}, ...allBuiltins, add),
  };

  const blockNumber = (receipt as any)["block_number"];
  const blockInfo = await provider.getBlock(blockNumber);
  const stateUpdate = await provider.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const gasPrice = BigInt(blockInfo.gas_price as string);
  const gasUsed = actualFee / gasPrice;

  // from https://docs.starknet.io/documentation/architecture_and_concepts/Fees/fee-mechanism/
  const gasWeights: Record<string, number> = {
    n_steps: 0.01,
    pedersen_builtin: 0.32,
    poseidon_builtin: 0.32,
    range_check_builtin: 0.16,
    ecdsa_builtin: 20.48,
    keccak_builtin: 20.48,
    ec_op_builtin: 10.24,
    bitwise_builtin: 0.64,
    output_builtin: 9999999999999, // Undefined in https://docs.starknet.io/documentation/architecture_and_concepts/Fees/fee-mechanism/
  };

  const gasPerComputationCategory = Object.fromEntries(
    Object.entries(executionResources)
      .filter(([resource]) => resource in gasWeights)
      .map(([resource, usage]) => [resource, Math.ceil(usage * gasWeights[resource])]),
  );
  const maxComputationCategory = maxBy(Object.entries(gasPerComputationCategory), ([, gas]) => gas)![0];
  const computationGas = BigInt(gasPerComputationCategory[maxComputationCategory]);
  const l1CalldataGas = gasUsed - computationGas;

  const sortedResources = Object.fromEntries(sortBy(Object.entries(executionResources), 0));

  return {
    actualFee,
    gasUsed,
    l1CalldataGas,
    computationGas,
    maxComputationCategory,
    gasPerComputationCategory,
    executionResources: omit(sortedResources, "n_memory_holes"),
    n_memory_holes: executionResources.n_memory_holes,
    gasPrice,
    storageDiffs,
  };
}

export async function reportProfile(table: Record<string, any>, name: string, response: InvokeFunctionResponse) {
  const report = await profileGasUsage(response);
  const { actualFee, gasUsed, computationGas, l1CalldataGas, executionResources } = report;
  console.dir(report, { depth: null });
  const feeUsd = Number(actualFee * ethUsd) / Number(10n ** 18n);
  table[name] = {
    actualFee: Number(actualFee),
    feeUsd: Number(feeUsd.toFixed(2)),
    gasUsed: Number(gasUsed),
    computationGas: Number(computationGas),
    l1CalldataGas: Number(l1CalldataGas),
    ...executionResources,
  };
}
