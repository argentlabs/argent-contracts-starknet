import { exec } from "child_process";
import fs from "fs";

const output = fs.readFileSync("./test-output.txt", "utf8");

const tests = [
  "test_argent_account::initialize",
  "test_argent_account::change_owner",
  "test_argent_account::change_guardian",
  "test_argent_account_signatures::valid_no_guardian",
  "test_argent_account_signatures::valid_with_guardian",
  "test_multisig_account::valid_initialize",
  "test_multisig_account::valid_initialize_two_signers",
  "test_multisig_signing::test_signature",
  "test_multisig_signing::test_double_signature",
];

const regexp = new RegExp(`(${tests.join("|")}) .*gas usage est.: (\\d+)`);

const report = output
  .split("\n")
  .sort()
  .map((line) => line.match(regexp)!)
  .filter(Boolean)
  .map(([, testName, gas]) => `${testName}: ${Number(gas).toLocaleString("en")} gas`)
  .join("\n");

const mode = process.argv[2];
if (mode === "--write") {
  fs.writeFileSync("./gas-report.txt", report);
} else if (mode === "--check") {
  fs.writeFileSync("./gas-report-new.txt", report);
  exec("diff gas-report.txt gas-report-new.txt", (err, stdout, stderr) => {
    if (stdout) {
      console.log(stdout);
      console.error("Changes to gas costs detected. Please review them and update the gas report if appropriate.\n");
      return process.exit(1);
    } else {
      console.log("✨  No changes to gas report.");
    }
  });
} else {
  console.log(`Usage: scarb run gas-report --[write|check]`);
}
