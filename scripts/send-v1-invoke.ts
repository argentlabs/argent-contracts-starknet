import { pick } from "lodash-es";
import { Account, Call, RPC, uint256 } from "starknet";
import { deployer, manager } from "../lib";

const deployerV1 = new Account(deployer, deployer.address, deployer.signer, undefined, RPC.ETransactionVersion.V2);

//////////////////// Configure the tx to send here: ///////////
const eth = await manager.tokens.ethContract();
const call = await eth.populateTransaction.transfer(deployerV1.address, uint256.bnToUint256(1000000000000000n));
// const call = await strk.populateTransaction.transfer(deployer.address, uint256.bnToUint256(10000000000000000000000n));
const maxFee = 1 * 1e15;
///////////////////////////////////////////////////////////////

const calls: Array<Call> = [pick(call, ["contractAddress", "calldata", "entrypoint"])];

const executionResult = await deployerV1.execute(calls, { maxFee: maxFee });
console.log(`transaction_hash: ${executionResult.transaction_hash}`);
