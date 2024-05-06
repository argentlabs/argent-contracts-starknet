import { pick } from "lodash-es";
import { Call, uint256 } from "starknet";
import { deployer, provider } from "../lib";

//////////////////// Configure the tx to send here: ///////////
const eth = await provider.tokens.ethContract();
const call = await eth.populateTransaction.transfer(deployer.address, uint256.bnToUint256(1000000000000000n));
// const call = await strk.populateTransaction.transfer(deployer.address, uint256.bnToUint256(10000000000000000000000n));
const maxFee = 1000000000000000n;
///////////////////////////////////////////////////////////////

const calls: Array<Call> = [pick(call, ["contractAddress", "calldata", "entrypoint"])];

const executionResult = await deployer.execute(calls, undefined, { maxFee: maxFee });
console.log(`transaction_hash: ${executionResult.transaction_hash}`);
