import { RawArgs } from "starknet";
import { baseUrl } from "./constants";

async function fundAccount(address: string) {
  await handlePost("mint", {
    address,
    amount: 1e18,
    lite: true,
  });
}

async function increaseTime(timeInSeconds: number | bigint) {
  const timeInSecondsAsNumber = Number(timeInSeconds);
  await handlePost("increase_time", {
    time: timeInSecondsAsNumber,
  });
}

async function setTime(timeInSeconds: number | bigint) {
  const timeInSecondsAsNumber = Number(timeInSeconds);
  await handlePost("set_time", {
    time: timeInSecondsAsNumber,
  });
}

async function handlePost(path: string, payload: RawArgs) {
  try {
    const response = await fetch(`${baseUrl}/${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      throw new Error(`HTTP error! Status: ${response.status}`);
    }
    return await response.json();
  } catch (error) {
    console.error(error);
  }
}

export { fundAccount, increaseTime, setTime };
