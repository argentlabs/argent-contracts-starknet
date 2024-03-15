import "dotenv/config";
import { declareFixtureContract, deployContract } from "../tests-integration/lib";

console.log("declaring");

const classHash = await declareFixtureContract("Sha256Cairo0");
console.log("class hash:", classHash);

const mockDapp = await deployContract("MockDapp");
console.log("mock dapp address:", mockDapp.address);

const result = await mockDapp.library_call(classHash, "sha256", ["0x42"]);
// const result = await mockDapp.get_number("0x42");

console.log("result:", result);
