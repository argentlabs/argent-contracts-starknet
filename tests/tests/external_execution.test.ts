import { expect } from "chai";
import { Call, CallData, Signer, WeierstrassSignatureType, ec, hash, num, stark } from "starknet";
import {
  ArgentSigner,
  ExternalCallsArguments,
  declareContract,
  deployAccount,
  deployerAccount,
  getExternalCalls,
  getExternalTransactionCall,
  getTypedDataHash,
  loadContract,
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

    it("Test external execution", async function () {
      const accountSigner = new ArgentSigner();
      const account = await deployAccount(argentAccountClassHash, accountSigner.ownerPrivateKey);

      const chainId = await provider.getChainId();
      const args: ExternalCallsArguments = {
        sender: deployerAccount.address,
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
      const { transaction_hash: transferTxHash } = await deployerAccount.execute(
        await getExternalTransactionCall(args, account.address, accountSigner, chainId),
      );
      const receipt = await provider.waitForTransaction(transferTxHash);
    });
  });
});
