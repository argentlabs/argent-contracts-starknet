import "dotenv/config";
import { declareFixtureContract, deployContract, loadContract } from "../tests-integration/lib";

console.log("declaring");

// const classHash = "0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d";
const classHash = await declareFixtureContract("Sha256Cairo0");
console.log("sha256 class hash:", classHash);

const mockDapp = await deployContract("MockDapp");
console.log("mock dapp address:", mockDapp.address);

const result = await mockDapp.library_call(classHash, "sha256_cairo0", ["0x42"]);
// const result = await mockDapp.get_number("0x42");

console.log("result:", result);
