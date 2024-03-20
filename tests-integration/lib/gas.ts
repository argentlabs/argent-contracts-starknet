import { exec } from "child_process";
import fs from "fs";
import { mapValues, maxBy, sortBy, sum } from "lodash-es";
import { InvokeFunctionResponse, RpcProvider, shortString } from "starknet";
import { ensureAccepted, ensureSuccess } from ".";

const ethUsd = 4000n;
const strkUsd = 2n;
const dataGasPrice = 1;

// from https://docs.starknet.io/documentation/architecture_and_concepts/Network_Architecture/fee-mechanism/
const gasWeights: Record<string, number> = {
  steps: 0.0025,
  pedersen: 0.08,
  poseidon: 0.08,
  range_check: 0.04,
  ecdsa: 5.12,
  keccak: 5.12,
  bitwise: 0.16,
  ec_op: 2.56,
};

async function profileGasUsage(transactionHash: string, provider: RpcProvider, allowFailedTransactions = false) {
  const receipt = await ensureAccepted(await provider.waitForTransaction(transactionHash));
  if (!allowFailedTransactions) {
    await ensureSuccess(receipt);
  }
  const actualFee = BigInt(receipt.actual_fee.amount);
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
    "segment_arena_builtin",
    "data_availability",
  ];
  // all keys in rawResources must be in expectedResources
  if (!Object.keys(rawResources).every((key) => expectedResources.includes(key))) {
    throw new Error(`unexpected execution resources: ${Object.keys(rawResources).join()}`);
  }

  const executionResources: Record<string, number> = {
    steps: rawResources.steps,
    pedersen: rawResources.pedersen_builtin_applications ?? 0,
    range_check: rawResources.range_check_builtin_applications ?? 0,
    poseidon: rawResources.poseidon_builtin_applications ?? 0,
    ecdsa: rawResources.ecdsa_builtin_applications ?? 0,
    keccak: rawResources.keccak_builtin_applications ?? 0,
    bitwise: rawResources.bitwise_builtin_applications ?? 0,
    ec_op: rawResources.ec_op_builtin_applications ?? 0,
  };

  const blockNumber = receipt.block_number;
  const blockInfo = await provider.getBlockWithReceipts(blockNumber);
  const stateUpdate = await provider.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const paidInStrk = receipt.actual_fee.unit == "FRI";
  const gasPrice = BigInt(paidInStrk ? blockInfo.l1_gas_price.price_in_fri : blockInfo.l1_gas_price.price_in_wei);

  // Removing the gas used for calldata/blob
  const gasUsed = (actualFee - BigInt(rawResources.data_availability.l1_data_gas * dataGasPrice)) / gasPrice;
  const gasPerComputationCategory = Object.fromEntries(
    Object.entries(executionResources)
      .filter(([resource]) => resource in gasWeights)
      .map(([resource, usage]) => [resource, Math.ceil(usage * gasWeights[resource])]),
  );
  const maxComputationCategory = maxBy(Object.entries(gasPerComputationCategory), ([, gas]) => gas)![0];
  const computationGas = BigInt(gasPerComputationCategory[maxComputationCategory]);

  const sortedResources = Object.fromEntries(sortBy(Object.entries(executionResources), 0));

  return {
    actualFee,
    paidInStrk,
    gasUsed,
    l1Gas: rawResources.data_availability.l1_gas,
    l1DataGas: rawResources.data_availability.l1_data_gas,
    computationGas,
    maxComputationCategory,
    gasPerComputationCategory,
    executionResources: sortedResources,
    gasPrice,
    storageDiffs,
  };
}

type Profile = Awaited<ReturnType<typeof profileGasUsage>>;

export function newProfiler(provider: RpcProvider, roundingMagnitude?: number) {
  const profiles: Record<string, Profile> = {};

  return {
    async profile(
      name: string,
      { transaction_hash }: InvokeFunctionResponse,
      { printProfile = false, printStorage = false, allowFailedTransactions = false } = {},
    ) {
      console.log(`Profiling: ${name} (${transaction_hash})`);
      const profile = await profileGasUsage(transaction_hash, provider, allowFailedTransactions);
      if (printProfile) {
        console.dir(profile, { depth: null });
      }
      if (printStorage) {
        this.printStorageDiffs(profile);
      }
      profiles[name] = profile;
    },
    summarizeCost(profile: Profile) {
      const usdVal = profile.paidInStrk ? strkUsd : ethUsd;
      const feeUsd = Number((10000n * profile.actualFee * usdVal) / 10n ** 18n) / 10000;
      return {
        actualFee: Number(profile.actualFee).toLocaleString("de-DE"),
        feeUsd: Number(feeUsd.toFixed(4)),
        gasUsed: Number(profile.gasUsed),
        computationGas: Number(profile.computationGas),
        storageDiffs: sum(profile.storageDiffs.map(({ storage_entries }) => storage_entries.length)),
        l1Gas: Number(profile.l1Gas),
        l1DataGas: Number(profile.l1DataGas),
        maxComputationCategory: profile.maxComputationCategory,
      };
    },
    printStorageDiffs({ storageDiffs }: Profile) {
      const diffs = storageDiffs.map(({ address, storage_entries }) =>
        storage_entries.map(({ key, value }) => ({
          address: shortenHex(address),
          key: shortenHex(key),
          hex: value,
          dec: BigInt(value),
          str: shortString.decodeShortString(value),
        })),
      );
      console.table(diffs.flat());
    },
    printSummary() {
      console.log("Summary:");
      console.table(mapValues(profiles, this.summarizeCost));
      console.log("Resources:");
      console.table(mapValues(profiles, "executionResources"));
    },
    formatReport() {
      return Object.entries(profiles)
        .map(([name, { gasUsed, maxComputationCategory }]) => {
          const roundingScale = 10 ** (roundingMagnitude ?? 0);
          const gasRounded = Math.round(Number(gasUsed) / roundingScale) * roundingScale;
          return `${name}: ${gasRounded.toLocaleString("en")} gas (${maxComputationCategory})`; // TODO ADD STORAGE DIFFS + L1 DATA GAS
        })
        .join("\n");
    },
    updateOrCheckReport() {
      const report = this.formatReport();
      const filename = "gas-report.txt";
      const newFilename = "gas-report-new.txt";
      fs.writeFileSync(newFilename, report);
      exec(`diff ${filename} ${newFilename}`, (err, stdout) => {
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

function shortenHex(hex: string) {
  return `${hex.slice(0, 6)}...${hex.slice(-4)}`;
}
