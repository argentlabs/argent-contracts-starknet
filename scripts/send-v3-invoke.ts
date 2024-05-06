import { Call, uint256 } from "starknet";
import { deployerV3, provider } from "../lib";

//////////////////// Configure the tx to send here: ///////////
const strk = await provider.tokens.strkContract();
// const call = await eth.populateTransaction.transfer("deployerV3.address", uint256.bnToUint256(42n));
const call = await strk.populateTransaction.transfer(deployerV3.address, uint256.bnToUint256(10000000000000000000000n));
///////////////////////////////////////////////////////////////

const calls: Array<Call> = [call];

const executionResult = await deployerV3.execute(calls);
console.log(`transaction_hash: ${executionResult.transaction_hash}`);
