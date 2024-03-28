import "dotenv/config";
import { shortString } from "starknet";
import { declareFixtureContract, deployContract } from "../tests-integration/lib";

// const classHash = "0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d";
const classHash = await declareFixtureContract("Sha256Cairo0");
console.log("sha256 class hash:", classHash);

const mockDapp = await deployContract("MockDapp");
console.log("mock dapp address:", mockDapp.address);

const message = "localhost".split("").map(shortString.encodeShortString);
const result = await mockDapp.doit(classHash, message);
console.log("result:", result);
