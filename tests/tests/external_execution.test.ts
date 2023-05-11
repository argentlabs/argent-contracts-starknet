import { expect } from "chai";
import { Call, CallData, Signer, WeierstrassSignatureType, hash, typedData } from "starknet";
import {
  ExternalCallsArguments,
  declareContract,
  deployAccount,
  account as deployer,
  getExternalCallsCallData,
  getExternalTransactionCallData,
  getTypedDataHash,
  provider,
} from "./shared";

describe.only("Test external execution", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  describe("Test external execution", function () {
    it("Test external execution", async function () {
      const account = await deployAccount(argentAccountClassHash);

      const ownerSigner = new Signer((account.signer as any)["pk"]);
      const chainId = await provider.getChainId();
      const args: ExternalCallsArguments = {
        sender: deployer.address,
        nonce: 2,
        min_timestamp: 0,
        max_timestamp: 1713139200,
        calls: [
          {
            contractAddress: account.address,
            entrypoint: hash.getSelectorFromName("get_owner"),
          },
        ],
      };

      const foundHash = (
        await provider.callContract({
          contractAddress: account.address,
          entrypoint: "get_hash_message_external_calls",
          calldata: getExternalCallsCallData(args),
        })
      ).result[0];
      const expectedMessageHash = await getTypedDataHash(args, account.address, chainId);
      expect(foundHash).to.equal(expectedMessageHash);

      const { transaction_hash: transferTxHash } = await deployer.execute([
        {
          contractAddress: account.address,
          entrypoint: "execute_external_calls",
          calldata: await getExternalTransactionCallData(args, account.address, ownerSigner, chainId),
        },
      ]);
      const receipt = await provider.waitForTransaction(transferTxHash);
    });
  });
});
