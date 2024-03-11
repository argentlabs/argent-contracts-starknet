import { RawArgs } from "starknet";
import { provider } from "./provider";

const DUMP_FOLDER_PATH = "./dump";

export async function mintEth(address: string, amount: number | bigint) {
  await handlePost("mint", { address, amount: Number(amount) });
}

export async function increaseTime(timeInSeconds: number | bigint) {
  await handlePost("increase_time", { time: Number(timeInSeconds) });
}

export async function setTime(timeInSeconds: number | bigint) {
  timeInSeconds = BigInt(timeInSeconds) + BigInt(7 * 24 * 60 * 60);
  await handlePost("set_time", { time: Number(timeInSeconds) });
}

export async function restart() {
  await handlePost("restart");
}

export async function dump() {
  await handlePost("dump", { path: DUMP_FOLDER_PATH });
}

export async function load() {
  await handlePost("load", { path: DUMP_FOLDER_PATH });
}

async function handlePost(path: string, payload?: RawArgs) {
  const url = `${provider.channel.nodeUrl}/${path}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new Error(`HTTP error! calling ${url} Status: ${response.status} Message: ${await response.text()}`);
  }
}
