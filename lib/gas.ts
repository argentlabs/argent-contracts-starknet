import { exec } from "child_process";
import fs from "fs";
import { mapValues, maxBy, sortBy, sum } from "lodash-es";
import { InvokeFunctionResponse, shortString } from "starknet";
import { type Manager } from "./manager";

const ethUsd = 2400;
const strkUsd = 0.4;

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

const l2PayloadsWeights: Record<string, number> = {
  eventKey: 0.256,
  eventData: 0.12,
  calldata: 0.128,
};

async function profileGasUsage(transactionHash: string, manager: Manager, allowFailedTransactions = false) {
  const receipt = await manager.ensureAccepted({ transaction_hash: transactionHash });
  if (!allowFailedTransactions) {
    await manager.ensureSuccess(receipt);
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
  const blockInfo = await manager.getBlockWithReceipts(blockNumber);

  const stateUpdate = await manager.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const paidInStrk = receipt.actual_fee.unit == "FRI";
  const gasPrice = BigInt(paidInStrk ? blockInfo.l1_gas_price.price_in_fri : blockInfo.l1_gas_price.price_in_wei);

  const gasPerComputationCategory = Object.fromEntries(
    Object.entries(executionResources)
      .filter(([resource]) => resource in gasWeights)
      .map(([resource, usage]) => [resource, Math.ceil(usage * gasWeights[resource])]),
  );
  const maxComputationCategory = maxBy(Object.entries(gasPerComputationCategory), ([, gas]) => gas)![0];
  const computationGas = BigInt(gasPerComputationCategory[maxComputationCategory]);

  let gasWithoutDa;
  let feeWithoutDa;
  let daFee;
  if (rawResources.data_availability) {
    const dataGasPrice = Number(
      paidInStrk ? blockInfo.l1_data_gas_price.price_in_fri : blockInfo.l1_data_gas_price.price_in_wei,
    );

    daFee = (rawResources.data_availability.l1_gas + rawResources.data_availability.l1_data_gas) * dataGasPrice;
    feeWithoutDa = actualFee - BigInt(daFee);
    gasWithoutDa = feeWithoutDa / gasPrice;
  } else {
    // This only happens for tx before Dencun
    gasWithoutDa = actualFee / gasPrice;
    daFee = gasWithoutDa - computationGas;
    feeWithoutDa = actualFee;
  }

  const sortedResources = Object.fromEntries(sortBy(Object.entries(executionResources), 0));

  // L2 payloads
  const tx = (await manager.getTransaction(receipt.transaction_hash)) as any;
  const calldataLen = tx.calldata?.length || tx.constructor_calldata.length;
  const calldataGas = Math.floor((calldataLen + tx.signature.length) * l2PayloadsWeights.calldata);

  const eventGas = Math.floor(
    receipt.events.reduce(
      (sum, { keys, data }) =>
        sum + keys.length * l2PayloadsWeights.eventKey + data.length * l2PayloadsWeights.eventData,
      0,
    ),
  );
  return {
    actualFee,
    paidInStrk,
    gasWithoutDa,
    feeWithoutDa,
    daFee,
    computationGas,
    maxComputationCategory,
    gasPerComputationCategory,
    executionResources: sortedResources,
    gasPrice,
    storageDiffs,
    daMode: blockInfo.l1_da_mode,
    calldataGas,
    eventGas,
  };
}

type Profile = Awaited<ReturnType<typeof profileGasUsage>>;

export function newProfiler(manager: Manager) {
  const profiles: Record<string, Profile> = {};

  return {
    async profile(
      name: string,
      transactionHash: InvokeFunctionResponse | string,
      { printProfile = false, printStorage = false, allowFailedTransactions = false } = {},
    ) {
      if (typeof transactionHash === "object") {
        transactionHash = transactionHash.transaction_hash;
      }
      console.log(`Profiling: ${name} (${transactionHash})`);
      const profile = await profileGasUsage(transactionHash, manager, allowFailedTransactions);
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
      const feeUsd = Number((profile.actualFee * BigInt(100000 * usdVal)) / 10n ** 18n) / 100000;
      return {
        "Actual fee": Number(profile.actualFee).toLocaleString("de-DE"),
        "Fee usd": Number(feeUsd.toFixed(5)),
        "Fee without DA": Number(profile.feeWithoutDa),
        "Gas without DA": Number(profile.gasWithoutDa),
        "Computation gas": Number(profile.computationGas),
        "Event gas": Number(profile.eventGas),
        "Calldata gas": Number(profile.calldataGas),
        "Max computation per Category": profile.maxComputationCategory,
        "Storage diffs": sum(profile.storageDiffs.map(({ storage_entries }) => storage_entries.length)),
        "DA fee": Number(profile.daFee),
        "DA mode": profile.daMode,
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
      // Capture console.table output into a variable
      let tableString = "";
      const log = console.log;
      console.log = (...args) => {
        tableString += args.join("") + "\n";
      };
      this.printSummary();
      // Restore console.log to its original function
      console.log = log;
      // Remove ANSI escape codes (colors) from the tableString
      tableString = tableString.replace(/\u001b\[\d+m/g, "");
      return tableString;
    },
    updateOrCheckReport() {
      const report = this.formatReport();
      const filename = "gas-report.txt";
      const newFilename = "gas-report-new.txt";
      fs.writeFileSync(newFilename, report);
      exec(`diff ${filename} ${newFilename}`, (_, stdout) => {
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
          console.error(`⚠️ Please update ${filename} and commit it in this PR.\n`);
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
