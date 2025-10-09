import * as env from "$env/static/public";
import { CallData, Contract, ETransactionVersion, ProviderInterface, RpcProvider, uint256 } from "starknet";
import { ArgentAccount } from "$lib/accounts";

export type ProviderType = RpcProvider;
let deployer: ArgentAccount | undefined;

export const strkAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
let strkContract: Contract;

export async function getStrkContract(provider: ProviderType) {
  if (strkContract) {
    return strkContract;
  }
  strkContract = await loadContract(strkAddress, provider);
  return strkContract;
}

export async function loadDeployer(provider: ProviderType) {
  if (deployer) {
    return deployer;
  }
  if (providerUrl(provider).includes("localhost")) {
    const [{ address, private_key }] = await predeployedAccounts(provider);
    return new ArgentAccount({
      provider,
      address,
      signer: private_key,
      cairoVersion: "1",
      transactionVersion: ETransactionVersion.V3,
    });
  }
  // Ignore warning about env.PUBLIC_DEPLOYER_ADDRESS and env.PUBLIC_DEPLOYER_PRIVATE_KEY
  // @ts-ignore
  if (!env.PUBLIC_DEPLOYER_ADDRESS || !env.PUBLIC_DEPLOYER_PRIVATE_KEY) {
    throw new Error("Need deployer credentials for non-devnet");
  }
  return new ArgentAccount({
    provider,
    // @ts-ignore
    address: env.PUBLIC_DEPLOYER_ADDRESS,
    // @ts-ignore
    signer: env.PUBLIC_DEPLOYER_PRIVATE_KEY,
    cairoVersion: undefined,
    transactionVersion: ETransactionVersion.V3,
  });
}

export async function loadContract(contractAddress: string, provider: ProviderInterface) {
  const { abi } = await provider.getClassAt(contractAddress);
  if (!abi) {
    throw new Error("Error while getting ABI");
  }
  return new Contract({
    abi,
    address: contractAddress,
    providerOrAccount: provider,
  });
}

export async function fundAccount(recipient: string, amount: number | bigint, provider: ProviderType) {
  console.log("funding account...");
  if (providerUrl(provider).includes("localhost")) {
    await mintStrk(recipient, provider);
    return;
  }
  const strkContract = await getStrkContract(provider);
  const deployer = await loadDeployer(provider);
  strkContract.providerOrAccount = deployer;

  console.log("sending STRK from deployer to new account");
  const bn = uint256.bnToUint256(amount);
  const { transaction_hash } = await strkContract.invoke("transfer", CallData.compile([recipient, bn]));
  console.log("waiting for funding tx", transaction_hash);
  await provider.waitForTransaction(transaction_hash);
}

export async function predeployedAccounts(
  provider: ProviderType,
): Promise<Array<{ address: string; private_key: string }>> {
  return handleJsonRpc(provider, "devnet_getPredeployedAccounts");
}

export async function mintStrk(address: string, provider: ProviderType) {
  await handleJsonRpc(provider, "devnet_mint", {
    address,
    amount: 100e18,
    unit: "FRI",
  });
}

async function handleJsonRpc(provider: ProviderInterface, method: string, params = {}) {
  const body = {
    jsonrpc: "2.0",
    id: Date.now(),
    method,
    params,
  };

  const res = await fetch(`${provider.channel.nodeUrl}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const json = await res.json();

  if (json.error) {
    throw new Error(`RPC Error: ${json.error.message}`);
  }

  return json.result;
}

function providerUrl(provider: ProviderInterface): string {
  return provider.channel.nodeUrl;
}
