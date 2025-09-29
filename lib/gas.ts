import { exec } from "child_process";
import fs from "fs";
import { InvokeFunctionResponse } from "starknet";
import { type Manager } from "./manager";

const strkUsd = 0.14;
// We could get the prices from the block, but it's not worth the extra complexity
const l1GasPrice = 45000000000000n;
const l2GasPrice = 3000000000n;
const l1DataGasPrice = 35000n;

async function profileGasUsage(transactionHash: string, manager: Manager, allowFailedTransactions = false) {
  const receipt = await manager.ensureAccepted({ transaction_hash: transactionHash });
  if (!allowFailedTransactions) {
    await manager.ensureSuccess(receipt);
  }

  if (receipt.actual_fee.unit != "FRI") {
    throw new Error("Unsupported fee unit");
  }

  const actualFee = BigInt(receipt.actual_fee.amount);
  const { l1_gas, l2_gas, l1_data_gas } = receipt.execution_resources;

  return {
    actualFee,
    l1_gas,
    l2_gas,
    l1_data_gas,
  };
}

type Profile = Awaited<ReturnType<typeof profileGasUsage>>;

export function newProfiler(manager: Manager) {
  const profiles: Record<string, Profile> = {};

  return {
    async profile(
      name: string,
      transactionHash: InvokeFunctionResponse | string,
      { printProfile = false, allowFailedTransactions = false } = {},
    ) {
      if (typeof transactionHash === "object") {
        transactionHash = transactionHash.transaction_hash;
      }
      console.log(`Profiling: ${name} (${transactionHash})`);
      const profile = await profileGasUsage(transactionHash, manager, allowFailedTransactions);
      if (printProfile) {
        console.dir(profile, { depth: null });
      }
      profiles[name] = profile;
    },
    summarizeCost(profile: Profile) {
      const multiplier = 1000000;
      const feeUsd = Number((profile.actualFee * BigInt(multiplier * strkUsd)) / 10n ** 18n) / multiplier;
      const l1GasFeeUsd = Number((l1GasPrice * BigInt(profile.l1_gas) * (BigInt(multiplier * strkUsd))) / 10n ** 18n )/ multiplier;
      const l2GasFeeUsd = Number((l2GasPrice * BigInt(profile.l2_gas) * (BigInt(multiplier * strkUsd))) / 10n ** 18n )/ multiplier;
      const l1DataGasFeeUsd = Number((l1DataGasPrice * BigInt(profile.l1_data_gas) * (BigInt(multiplier * strkUsd))) / 10n ** 18n )/ multiplier;
      return {
        "Actual fee": Number(profile.actualFee).toLocaleString("de-DE"),
        "Fee usd": Number(feeUsd.toFixed(6)),
        "L1 gas": profile.l1_gas,
        "L1 gas fee usd": Number(l1GasFeeUsd.toFixed(6)),
        "L2 gas": profile.l2_gas,
        "L2 gas fee usd": Number(l2GasFeeUsd.toFixed(6)),
        "L1 data gas": profile.l1_data_gas,
        "L1 data fee usd": Number(l1DataGasFeeUsd.toFixed(6)),
      };
    },
    printSummary() {
      console.log("Summary:");
      const summary = Object.entries(profiles).map(([name, profile]) => ({
        Name: name,
        ...this.summarizeCost(profile),
      }));
      const table = Object.fromEntries(summary.map(({ Name, ...rest }) => [Name, rest]));
      console.table(table);
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
    updateOrCheckReport(write = false) {
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
        if (write || process.argv.includes("--write")) {
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
