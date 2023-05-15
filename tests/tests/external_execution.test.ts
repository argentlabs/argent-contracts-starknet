import { expect } from "chai";
import { hash, InvokeFunctionResponse, num } from "starknet";
import {
  ArgentSigner,
  declareContract,
  deployAccount,
  deployerAccount,
  expectRevertWithErrorMessage,
  ExternalExecutionArgs,
  getExternalExecution,
  getExternalExecutionCall,
  getTypedDataHash,
  loadContract,
  provider,
  waitForExecution,
} from "./shared";
import { profileGasUsage } from "./shared/gasUsage";

describe.only("Test external execution", function () {
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
      const args: ExternalExecutionArgs = {
        sender: deployerAccount.address,
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
        await accountContract.get_message_hash_external_execution(getExternalExecution(args), { nonce: undefined }),
      );
      const expectedMessageHash = getTypedDataHash(args, account.address, chainId);
      expect(foundHash).to.equal(expectedMessageHash);
    });

    it("Test external execution", async function () {
      const accountSigner = new ArgentSigner();
      const account = await deployAccount(argentAccountClassHash, accountSigner.ownerPrivateKey);

      const chainId = await provider.getChainId();
      const args: ExternalExecutionArgs = {
        sender: deployerAccount.address,
        min_timestamp: 0,
        max_timestamp: 1713139200,
        calls: [
          {
            contractAddress: account.address,
            entrypoint: hash.getSelectorFromName("get_owner"),
          },
        ],
      };

      await waitForExecution(
        deployerAccount.execute(await getExternalExecutionCall(args, account.address, accountSigner, chainId)),
      );

      await waitForExecution(
        deployerAccount.execute(
          await getExternalExecutionCall(
            { ...args, max_timestamp: 1713139201 },
            account.address,
            accountSigner,
            chainId,
          ),
        ),
      );
      await expectRevertWithErrorMessage("argent/repeated-external-exec", async () => {
        await deployerAccount.execute(await getExternalExecutionCall(args, account.address, accountSigner, chainId));
      });
    });
  });
});
