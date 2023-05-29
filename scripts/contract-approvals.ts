import { Octokit } from "@octokit/rest";

const octokit = new Octokit();

console.log("Hello, world!");

const { data: pr } = await octokit.rest.pulls.get({
  owner: "argentlabs",
  repo: "argent-contracts-starknet-private",
  pull_number: 141,
});
console.log("pr", pr);
