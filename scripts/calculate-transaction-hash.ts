import { CallData, EDAMode, ETransactionVersion, hash } from "starknet";

const tx = {
  type: "INVOKE",
  sender_address: "0x0000000000000000000000000000000000000000000000000000000000000000",
  calldata: [],
  signature: [],
  nonce: "0x0",
  resource_bounds: {
    l1_gas: {
      max_amount: "0x0",
      max_price_per_unit: "0x1",
    },
    l2_gas: {
      max_amount: "0x1",
      max_price_per_unit: "0x1",
    },
    l1_data_gas: {
      max_amount: "0x1",
      max_price_per_unit: "0x1",
    },
  },
  tip: "0x0",
  paymaster_data: [],
  nonce_data_availability_mode: "L1",
  fee_data_availability_mode: "L1",
  account_deployment_data: [],
  version: "0x3",
};

const txHash = hash.calculateInvokeTransactionHash({
  senderAddress: tx.sender_address,
  version: ETransactionVersion.V3,
  compiledCalldata: CallData.compile(tx.calldata),
  chainId: "0x534e5f4d41494e",
  nonce: tx.nonce,
  accountDeploymentData: tx.account_deployment_data,
  nonceDataAvailabilityMode: EDAMode.L1,
  feeDataAvailabilityMode: EDAMode.L1,
  resourceBounds: {
    l1_gas: {
      max_amount: BigInt(tx.resource_bounds.l1_gas.max_amount),
      max_price_per_unit: BigInt(tx.resource_bounds.l1_gas.max_price_per_unit),
    },
    l2_gas: {
      max_amount: BigInt(tx.resource_bounds.l2_gas.max_amount),
      max_price_per_unit: BigInt(tx.resource_bounds.l2_gas.max_price_per_unit),
    },
    l1_data_gas: {
      max_amount: BigInt(tx.resource_bounds.l1_data_gas.max_amount),
      max_price_per_unit: BigInt(tx.resource_bounds.l1_data_gas.max_price_per_unit),
    },
  },
  tip: tx.tip,
  paymasterData: tx.paymaster_data,
});

console.log(txHash);
