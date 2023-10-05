import { exec } from "child_process";
import fs from "fs";

const output = fs.readFileSync("./test-output.txt", "utf8");

const tests = [
  "test_argent_account::initialize",
  "test_argent_account::change_owner",
  "test_argent_account::change_guardian",
];

// capturing gas usage:
const regexp = new RegExp(`^.*(${tests.join("|")}).*gas usage est.: (\\d+).*$`);

console.log(regexp, regexp.toString());
const all = output
  .split("\n")
  .map((line) => line.match(regexp))
  .filter(Boolean);

for (const item of all) {
  const [, testName, gas] = item!;
  console.log(item);
  console.log("------------------");
}
