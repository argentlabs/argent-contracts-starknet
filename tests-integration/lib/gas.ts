import { maxBy, omit, sortBy } from "lodash-es";
import { provider } from "./provider";
import { ensureIncluded } from "./receipts";
const ethUsd = 2000n;

interface TransactionCarrying {
  transaction_hash: string;
}

async function profileGasUsage(transactionHash: string) {
  const receipt = ensureIncluded(await provider.waitForTransaction(transactionHash));
  if (receipt.actual_fee.unit !== "WEI") {
    throw new Error(`unexpected fee unit: ${receipt.actual_fee.unit}`);
  }
  const actualFee = BigInt(receipt.actual_fee.amount);
  const rawResources = (receipt as any).execution_resources!;

  const expectedResources = [
    "steps",
    "memory_holes",
    "range_check_builtin_applications",
    "pedersen_builtin_applications",
    "poseidon_builtin_applications",
    "ec_op_builtin_applications",
    "ecdsa_builtin_applications",
    "bitwise_builtin_applications",
    "keccak_builtin_applications",
  ];
  // all keys in rawResources must be in expectedResources
  if (!Object.keys(rawResources).every((key) => expectedResources.includes(key))) {
    throw new Error(`unexpected execution resources: ${Object.keys(rawResources).join()}`);
  }

  const executionResources: Record<string, number> = {
    n_steps: Number(rawResources.steps ?? 0),
    n_memory_holes: Number(rawResources.memory_holes ?? 0),
    pedersen_builtin: Number(rawResources.pedersen_builtin_applications ?? 0),
    poseidon_builtin: Number(rawResources.poseidon_builtin_applications ?? 0),
    range_check_builtin: Number(rawResources.range_check_builtin_applications ?? 0),
    ecdsa_builtin: Number(rawResources.ecdsa_builtin_applications ?? 0),
    keccak_builtin: Number(rawResources.keccak_builtin_applications ?? 0),
    ec_op_builtin: Number(rawResources.ec_op_builtin_applications ?? 0),
    bitwise_builtin: Number(rawResources.bitwise_builtin_applications ?? 0),
  };

  const blockNumber = receipt.block_number;
  const blockInfo = await provider.getBlockWithTxHashes(blockNumber);
  const stateUpdate = await provider.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const gasPrice = BigInt(blockInfo.l1_gas_price.price_in_wei);
  const gasUsed = actualFee / gasPrice;

  // from https://docs.starknet.io/documentation/architecture_and_concepts/Network_Architecture/fee-mechanism/
  const gasWeights: Record<string, number> = {
    n_steps: 0.01,
    pedersen_builtin: 0.32,
    poseidon_builtin: 0.32,
    range_check_builtin: 0.16,
    ecdsa_builtin: 20.48,
    keccak_builtin: 20.48,
    ec_op_builtin: 10.24,
    bitwise_builtin: 0.64,
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

async function reportProfile(table: Record<string, any>, name: string, transactionHash: string) {
  const report = await profileGasUsage(transactionHash);
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

export function makeProfiler() {
  const table: Record<string, any> = {};

  return {
    async profile(name: string, { transaction_hash }: TransactionCarrying) {
      return await reportProfile(table, name, transaction_hash);
    },
    printReport() {
      console.table(table);
    },
  };
}
