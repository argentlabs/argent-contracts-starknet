import { exec } from "child_process";

const minApprovers = parseInt(process.argv[2]);
if (Number.isNaN(minApprovers)) {
  console.error("Usage: yarn ts-node ./scripts/contract-approvals.ts <min approvers number>");
  process.exit(1);
}

exec("gh pr view 141 --json files,reviews", (err, stdout, stderr) => {
  if (stderr) {
    console.error(stderr);
  }
  if (err) {
    throw err;
  }
  const { files, reviews } = JSON.parse(stdout) as Record<string, Array<any>>;

  const contractsChanged = files.map(({ path }) => path).filter((path: string) => path.match(/\.(sol|cairo)$/));
  if (contractsChanged.length === 0) {
    console.log("✨ No smart contracts changes");
    return;
  }

  const approvals = reviews.filter(({ state }) => state === "APPROVED").map(({ author }) => author.login);
  const approvers = new Set(approvals).size;
  if (approvers < minApprovers) {
    console.error(`Need at least ${minApprovers} approvers for smart contract changes, got ${approvals.length}`);
    return process.exit(1);
  } else {
    console.log(`✨ ${approvers} approvers for smart contract changes`);
  }
});
