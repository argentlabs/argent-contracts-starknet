import { exec } from "child_process";
import fs from "fs";
import { isUndefined, mapValues, maxBy, omit, sortBy, sum } from "lodash-es";
import { RpcProvider } from "starknet";
import { ensureIncluded } from ".";

const ethUsd = 2500n;
const gwei = 10n ** 9n;
const gasPrice = 30n * gwei;

export interface TransactionCarrying {
  transaction_hash: string;
}

async function profileGasUsage(transactionHash: string, provider: RpcProvider) {
  const receipt = ensureIncluded(await provider.waitForTransaction(transactionHash));
  let actualFee = 0n;
  if (receipt.actual_fee.unit === "WEI") {
    actualFee = BigInt(receipt.actual_fee.amount);
  } else if (isUndefined(receipt.actual_fee.unit)) {
    actualFee = BigInt(receipt.actual_fee as any);
  } else {
    throw new Error(`unexpected fee: ${receipt.actual_fee}`);
  }
  const rawResources = receipt.execution_resources!;

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
    pedersen: Number(rawResources.pedersen_builtin_applications ?? 0),
    poseidon: Number(rawResources.poseidon_builtin_applications ?? 0),
    range_check: Number(rawResources.range_check_builtin_applications ?? 0),
    ecdsa: Number(rawResources.ecdsa_builtin_applications ?? 0),
    keccak: Number(rawResources.keccak_builtin_applications ?? 0),
    ec_op: Number(rawResources.ec_op_builtin_applications ?? 0),
    bitwise: Number(rawResources.bitwise_builtin_applications ?? 0),
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
    pedersen: 0.32,
    poseidon: 0.32,
    range_check: 0.16,
    ecdsa: 20.48,
    keccak: 20.48,
    ec_op: 10.24,
    bitwise: 0.64,
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
    storageDiffsCount: sum(storageDiffs.map(({ storage_entries }) => storage_entries.length)),
  };
}

type Profile = Awaited<ReturnType<typeof profileGasUsage>>;

export function newProfiler(provider: RpcProvider, gasRoundingDecimals?: number) {
  const profiles: Record<string, Profile> = {};

  return {
    async profile(name: string, { transaction_hash }: TransactionCarrying, print = false) {
      console.log("Profiling:", name);
      const profile = await profileGasUsage(transaction_hash, provider);
      if (print) {
        console.dir(profile, { depth: null });
      }
      profiles[name] = profile;
    },
    summarizeCost(profile: Profile) {
      const feeUsd = Number((10000n * profile.actualFee * ethUsd) / 10n ** 18n) / 10000;
      const feeUsdAdjusted = (feeUsd * Number(gasPrice)) / Number(profile.gasPrice);
      return {
        actualFee: Number(profile.actualFee),
        feeUsd: Number(feeUsdAdjusted.toFixed(2)),
        gasUsed: Number(profile.gasUsed),
        storageDiffs: profile.storageDiffsCount,
        computationGas: Number(profile.computationGas),
        l1CalldataGas: Number(profile.l1CalldataGas),
      };
    },
    printProfiles() {
      console.log("Resources:");
      console.table(mapValues(profiles, "executionResources"));
      console.log("Costs:");
      console.table(mapValues(profiles, this.summarizeCost));
    },
    formatReport() {
      return Object.entries(profiles)
        .map(([name, { gasUsed }]) => {
          const roundingScale = 10 ** (gasRoundingDecimals ?? 1);
          const gasRounded = Math.round(Number(gasUsed) / roundingScale) * roundingScale;
          return `${name}: ${gasRounded.toLocaleString("en")} gas`;
        })
        .join("\n");
    },
    updateOrCheckReport() {
      const report = this.formatReport();
      const filename = "gas-report.txt";
      const newFilename = "gas-report-new.txt";
      fs.writeFileSync(newFilename, report);
      exec(`diff ${filename} ${newFilename}`, (err, stdout, stderr) => {
        if (stdout) {
          console.log(stdout);
          console.error("⚠️  Changes to gas report detected.\n");
        } else {
          console.log("✨  No changes to gas report.");
        }
        fs.unlinkSync(newFilename);
        if (!stdout) {
          return;
        }
        if (process.argv.includes("--write")) {
          fs.writeFileSync(filename, report);
          console.log("✨  Gas report updated.");
        } else if (process.argv.includes("--check")) {
          console.error(`⚠️  Please update ${filename} and commit it in this PR.\n`);
          return process.exit(1);
        } else {
          console.log(`Usage: append either --write or --check to the CLI command.`);
        }
      });
    },
  };
}
