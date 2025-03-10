import { existsSync, readFileSync, writeFileSync } from "fs";
import { DeclareContractPayload, extractContractHashes } from "starknet";

// TODO We'd prob wanna have a better file
const cacheClassHash = "./target/cache.json";

// Caching ClassHash and CompiledClassHash
// On my machine approx 7s for compiledClassHash and 3s for classHash
// ClassHash is for CASM
// CompiledClassHash is for SIERRA

// TODO 4. at the end of the test, we write the cache ?

let cache: Record<string, { compiledClassHash: string | undefined; classHash: string }> = {};

if (!existsSync(cacheClassHash)) {
  writeFileSync(cacheClassHash, "{}");
}

try {
  cache = JSON.parse(readFileSync(cacheClassHash).toString("ascii"));
} catch (e) {
  console.log("Error reading cache", e);
}

export function populatePayloadWithClassHashes(payload: DeclareContractPayload, contractName: string) {
  if (!cache[contractName]) {
    const { compiledClassHash, classHash } = extractContractHashes(payload);
    cache[contractName] = { compiledClassHash, classHash };
    console.log(`Updating cache for ${contractName}`);
    writeFileSync(cacheClassHash, JSON.stringify(cache, null, 2));
  }
  payload.compiledClassHash = cache[contractName].compiledClassHash;
  payload.classHash = cache[contractName].classHash;
}

export function removeFromCache(contractName: string) {
  delete cache[contractName];
  writeFileSync(cacheClassHash, JSON.stringify(cache, null, 2));
}
