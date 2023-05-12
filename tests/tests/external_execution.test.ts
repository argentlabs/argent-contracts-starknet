import { expect } from "chai";
import { hash, InvokeFunctionResponse, num } from "starknet";
import {
  ArgentSigner,
  declareContract,
  deployAccount,
  deployerAccount,
  expectRevertWithErrorMessage,
  ExternalCallsArguments,
  getExternalCalls,
  getExternalTransactionCall,
  getTypedDataHash,
  loadContract,
  provider,
} from "./shared";

describe("Test external execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  describe("Test external execution", function () {
    it("Test correct hash", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account.address);

      const chainId = await provider.getChainId();
      const args: ExternalCallsArguments = {
        sender: deployerAccount.address,
        nonce: 2,
        min_timestamp: 0,
        max_timestamp: 1713139200,
        calls: [
          {
            contractAddress: "0x0424242",
            entrypoint: hash.getSelectorFromName("whatever_method"),
            calldata: ["0x0", "0x1"],
          },
        ],
      };

      const foundHash = num.toHex(
        await accountContract.get_hash_message_external_calls(getExternalCalls(args), { nonce: undefined }),
      );
      const expectedMessageHash = getTypedDataHash(args, account.address, chainId);
      expect(foundHash).to.equal(expectedMessageHash);
    });

    it.only("Test external execution", async function () {
      const accountSigner = new ArgentSigner();
      const account = await deployAccount(argentAccountClassHash, accountSigner.ownerPrivateKey);

      const chainId = await provider.getChainId();
      const args: ExternalCallsArguments = {
        sender: deployerAccount.address,
        nonce: 0,
        min_timestamp: 0,
        max_timestamp: 1713139200,
        calls: [
          {
            contractAddress: account.address,
            entrypoint: hash.getSelectorFromName("get_owner"),
          },
        ],
      };

      await profile(
        deployerAccount.execute(await getExternalTransactionCall(args, account.address, accountSigner, chainId)),
      );

      await profile(
        deployerAccount.execute(
          await getExternalTransactionCall({ ...args, nonce: 1 }, account.address, accountSigner, chainId),
        ),
      );
      await expectRevertWithErrorMessage("argent/invalid-nonce", async () => {
        await deployerAccount.execute(await getExternalTransactionCall(args, account.address, accountSigner, chainId));
      });
    });
  });
});

async function profile(functionCall: Promise<InvokeFunctionResponse>) {
  const { transaction_hash: transferTxHash } = await functionCall;
  const receipt = await provider.waitForTransaction(transferTxHash);
  const actualFee = num.hexToDecimalString(receipt.actual_fee as string) as unknown as number;
  const executionResources = (receipt as any)["execution_resources"];
  const blockNumber = (receipt as any)["block_number"];
  const blockInfo = await provider.getBlock(blockNumber);
  const stateUpdate = await provider.getStateUpdate(blockNumber);
  const storageDiffs = stateUpdate.state_diff.storage_diffs;
  const gasPrice = num.hexToDecimalString(blockInfo.gas_price as string) as unknown as number;
  const gasUsed = actualFee / gasPrice;
  // TODO there are more built-ins
  // from https://docs.starknet.io/documentation/architecture_and_concepts/Fees/fee-mechanism/
  const gasWeights: { [categoryName: string]: number } = {
    n_steps: 0.01,
    pedersen_builtin: 0.32,
    range_check_builtin: 0.16,
    ec_op_builtin: 10.24,
  };

  const executionResourcesFlat: { [categoryName: string]: number } = {
    ...executionResources.builtin_instance_counter,
    n_steps: executionResources.n_steps,
  };
  const gasPerComputationCategory: { [categoryName: string]: number } = Object.entries(executionResourcesFlat)
    .filter(([resource, usage]) => resource in gasWeights)
    .map(([resource, usage]) => [resource, Math.ceil(usage * gasWeights[resource])])
    .reduce((acc: { [categoryName: string]: number }, [resource, value]) => {
      acc[resource] = value as number;
      return acc;
    }, {});
  const maxComputationCategory: string = Object.keys(gasPerComputationCategory).reduce((a, b) => {
    return gasPerComputationCategory[a] > gasPerComputationCategory[b] ? a : b;
  });
  const computationGas = gasPerComputationCategory[maxComputationCategory];
  const l1Gas = gasUsed - computationGas;
  const gasUsage = {
    actualFee,
    gasUsed,
    l1Gas,
    computationGas,
    maxComputationCategory,
    gasPerComputationCategory,
    executionResources: executionResourcesFlat,
    n_memory_holes: executionResources.n_memory_holes,
    gasPrice,
    storageDiffs,
  };
  console.log(`${JSON.stringify(gasUsage)}`);

  return receipt;
}
