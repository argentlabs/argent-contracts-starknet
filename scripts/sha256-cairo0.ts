import "dotenv/config";
import { declareFixtureContract, deployContract } from "../tests-integration/lib";
import { hash } from "starknet";

console.log("declaring");

// const classHash = "0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d";
const classHash = await declareFixtureContract("Sha256Cairo0");
console.log("sha256 class hash:", classHash);

const mockDapp = await deployContract("MockDapp");
console.log("mock dapp address:", mockDapp.address);

const selector = hash.getSelectorFromName("sha256_cairo0");
const calldata = [0, 0];
const result = await mockDapp.library_call(classHash, selector, calldata);

console.log("result:", result);
