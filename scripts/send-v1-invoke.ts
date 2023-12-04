import { uint256, Call } from "starknet";
import { deployer, getEthContract } from "../tests-integration/lib";

//////////////////// Configure the tx to send here: ///////////
const call = await (
  await getEthContract()
).populateTransaction.transfer(deployer.address, uint256.bnToUint256(1000000000000000n));
// const call = await strk.populateTransaction.transfer(deployer.address, uint256.bnToUint256(10000000000000000000000n));
const maxFee = 1000000000000000n;
///////////////////////////////////////////////////////////////

const calls: Array<Call> = [
  {
    contractAddress: call.contractAddress,
    calldata: call.calldata,
    entrypoint: call.entrypoint,
  },
];

const executionResult = await deployer.execute(calls, undefined, { maxFee: maxFee });
console.log(`transaction_hash: ${executionResult.transaction_hash}`);
