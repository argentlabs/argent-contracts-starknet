import { RawArgs } from "starknet";
import { baseUrl } from "./constants";

export async function fundAccount(address: string) {
  await handlePost("mint", { address, amount: 1e18, lite: true });
}

export async function increaseTime(timeInSeconds: number | bigint) {
  await handlePost("increase_time", { time: Number(timeInSeconds) });
}

export async function setTime(timeInSeconds: number | bigint) {
  await handlePost("set_time", { time: Number(timeInSeconds) });
}

async function handlePost(path: string, payload: RawArgs) {
  try {
    const response = await fetch(`${baseUrl}/${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      throw new Error(`HTTP error! Status: ${response.status}`);
    }
    return await response.json();
  } catch (error) {
    console.error(error);
    throw error;
  }
}
