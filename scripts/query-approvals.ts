import "dotenv/config";
import { hash, num } from "starknet";
import { manager } from "../lib";

const address = "0x21935fa030b741808c639445d7c76027d9e38cedfd02fca188b4a8f1956cd6d";

// TODO NFTs
// TODO approvals without indexed fields

const CHUNK_SIZE = 100;
const SLEEP_TIME = 1000;
const lastBlock = (await manager.getBlock("latest")).block_number;
const keys = [[num.toHex(hash.starknetKeccak("Approval"))], [address]];

async function fetchAllEvents(
  minBlock: number,
  endBlock: number,
  keys: string[][],
  address?: string,
  continuationToken?: string,
): Promise<any[]> {
  console.log(
    `Querying events from ${minBlock} to ${endBlock} (${endBlock - minBlock} blocks), continuation token: ${continuationToken}`,
  );
  const response = await manager.getEvents({
    address,
    from_block: { block_number: minBlock },
    to_block: { block_number: endBlock },
    keys,
    chunk_size: CHUNK_SIZE,
    continuation_token: continuationToken,
  });

  const events = response.events;
  if (events.length > 0) {
    console.log(`Got ${events.length} events`);
  }
  if (response.continuation_token) {
    await new Promise((resolve) => setTimeout(resolve, SLEEP_TIME));
    return [...events, ...(await fetchAllEvents(minBlock, endBlock, keys, address, response.continuation_token))];
  } else {
    return events;
  }
}

const allEvents = await fetchAllEvents(0, lastBlock, keys);

const tokenAndSpenders = new Set<string>();
for (const event of allEvents) {
  const key = `${event.from_address}-${event.keys[2]}`;
  tokenAndSpenders.add(key);
}

console.log(`Found ${tokenAndSpenders.size} token and spenders`);
const tokenAndSpendersWithApprovals = new Set<string>();

for (const key of tokenAndSpenders) {
  const [token, spender] = key.split("-");
  try {
    // TODO multicall
    const allowance = await manager.callContract({
      contractAddress: token,
      entrypoint: "allowance",
      calldata: [address, spender],
    });

    if (num.toBigInt(allowance[0]) !== 0n || num.toBigInt(allowance[0]) !== 0n) {
      tokenAndSpendersWithApprovals.add(key);
    }
  } catch (error) {
    console.error(`Failed to check allowance for token ${token} spender ${spender}`);
  }
}
console.log(tokenAndSpendersWithApprovals.size);

const revokeMulticall = [];
for (const key of tokenAndSpendersWithApprovals) {
  const [token, spender] = key.split("-");
  revokeMulticall.push({
    contract_address: token,
    entry_point: "approve",
    calldata: [spender, "0x0", "0x0"],
  });
}
console.log(JSON.stringify(revokeMulticall));
