import { uint256, Call } from "starknet";
import { deployerV3, getStrkContract } from "../tests-integration/lib";

//////////////////// Configure the tx to send here: ///////////
const strk = await getStrkContract();
// const call = await eth.populateTransaction.transfer("deployerV3.address", uint256.bnToUint256(42n));
const call = await strk.populateTransaction.transfer(deployerV3.address, uint256.bnToUint256(10000000000000000000000n));
///////////////////////////////////////////////////////////////

const calls: Array<Call> = [
  {
    contractAddress: call.contractAddress,
    calldata: call.calldata,
    entrypoint: call.entrypoint,
  },
];

const executionResult = await deployerV3.execute(calls);
console.log(`transaction_hash: ${executionResult.transaction_hash}`);
