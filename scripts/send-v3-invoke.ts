import { Call, uint256 } from "starknet";
import { deployer, manager } from "../lib";

//////////////////// Configure the tx to send here: ///////////
const strk = await manager.tokens.strkContract();
// const call = await eth.populateTransaction.transfer("deployer.address", uint256.bnToUint256(42n));
const call = await strk.populateTransaction.transfer(deployer.address, uint256.bnToUint256(10000000000000000000000n));
///////////////////////////////////////////////////////////////

const calls: Array<Call> = [call];

const executionResult = await deployer.execute(calls);
console.log(`transaction_hash: ${executionResult.transaction_hash}`);
