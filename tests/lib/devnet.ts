import { RawArgs } from "starknet";
import { baseUrl } from "./provider";

const DUMP_FOLDER_PATH = "./dump";

export async function fundAccount(address: string) {
  await handlePost("mint", { address, amount: 1e18, lite: true });
}

export async function increaseTime(timeInSeconds: number | bigint) {
  await handlePost("increase_time", { time: Number(timeInSeconds) });
}

export async function setTime(timeInSeconds: number | bigint) {
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
  const response = await fetch(`${baseUrl}/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new Error(`HTTP error! Status: ${response.status} Message: ${await response.text()}`);
  }
}
