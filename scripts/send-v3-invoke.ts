import {
  uint256,
  num,
  ec,
  v3hash,
  V3TransactionDetails,
  InvocationsSignerDetails,
  Call,
  Calldata,
  RPC,
} from "starknet";
import { provider, deployer, loadContract } from "../tests-integration/lib";

//////////////////// Configure the tx to send here: ///////////
const strk = await loadContract("0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d");
// const call = await eth.populateTransaction.transfer("0x7948bc17a58063c4cebc3eadc2e2f9774710809c614b43bbb0093b0cffc0b52", uint256.bnToUint256(42n));
const call = await strk.populateTransaction.transfer(deployer.address, uint256.bnToUint256(10000000000000000000000n));
const maxL1Gas = 10000000n;
///////////////////////////////////////////////////////////////

const chainId = await provider.getChainId();
const block = await provider.getBlockWithTxHashes();

const calls: Array<Call> = [
  {
    contractAddress: call.contractAddress,
    calldata: call.calldata,
    entrypoint: call.entrypoint,
  },
];

const signerDetails: InvocationsSignerDetails = {
  walletAddress: deployer.address,
  nonce: 0,
  maxFee: 0n,
  version: 1n,
  chainId,
  cairoVersion: await deployer.getCairoVersion(),
};
const invocation = await deployer.buildInvocation(calls, signerDetails);
const calldata = invocation.calldata as Calldata;

const v3Details: V3TransactionDetails = {
  nonce: await deployer.getNonce(),
  version: 3n,
  resourceBounds: {
    l1_gas: {
      max_amount: num.toHex(maxL1Gas),
      max_price_per_unit: num.toHex(num.toBigInt(block.l1_gas_price.price_in_fri) * 2n),
    },
    l2_gas: {
      max_amount: "0x0",
      max_price_per_unit: "0x0",
    },
  },
  tip: 0n,
  paymasterData: [],
  accountDeploymentData: [],
  nonceDataAvailabilityMode: "L1",
  feeDataAvailabilityMode: "L1",
};

const txHash = v3hash.calculateInvokeTransactionHash(
  deployer.address,
  v3Details.version,
  calldata,
  chainId,
  v3Details.nonce,
  [], // accountDeploymentData
  RPC.EDAMode.L1,
  RPC.EDAMode.L1,
  v3Details.resourceBounds,
  v3Details.tip,
  [], //paymasterData
);

const signature = ec.starkCurve.sign(txHash, (deployer.signer as any)["pk"]);

const invocationResult = await provider.invokeFunction(
  { contractAddress: deployer.address, calldata, signature },
  v3Details,
);
console.log(`transaction_hash: ${invocationResult.transaction_hash}`);
