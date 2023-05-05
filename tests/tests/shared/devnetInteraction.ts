import { RawArgs } from "starknet";
import { baseUrl } from "./constants";

async function fundAccount(address: string) {
  await handlePost("mint", {
    address,
    amount: 18e18,
    lite: true,
  });
}

async function increaseTime(timeInSeconds: number) {
  await handlePost("increase_time", {
    time: timeInSeconds,
  });
}

async function setTime(timeInSeconds: number) {
  await handlePost("set_time", {
    time: timeInSeconds,
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
