import { expect } from "chai";
import { Call, CallData, Signer, WeierstrassSignatureType, hash, typedData } from "starknet";
import {
  declareContract,
  deployAccount,
  account as deployer,
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
    it("Test external execution", async function () {
      const account = await deployAccount(argentAccountClassHash);
      // const accountContract = await loadContract(account.address);

      const ownerSigner = new Signer((account.signer as any)["pk"]);

      const nonce = 2;
      const min_timestamp = 0;
      const max_timestamp = 1713139200;
      const sender = deployer.address;
      const calls: Call[] = [
        {
          contractAddress: account.address,
          entrypoint: hash.getSelectorFromName("get_owner"),
          calldata: [],
        },
      ];

      const chainId = await provider.getChainId();

      const externalCalls = {
        sender: sender,
        nonce,
        min_timestamp,
        max_timestamp,
        calls: calls.map((call) => {
          return {
            to: call.contractAddress,
            selector: call.entrypoint,
            calldata : call.calldata ?? []
          };
        }),
      };

      const types = {
        StarkNetDomain: [
          { name: "name", type: "felt" },
          { name: "version", type: "felt" },
          { name: "chainId", type: "felt" },
        ],
        ExternalCalls: [
          { name: "sender", type: "felt" },
          { name: "nonce", type: "felt" },
          { name: "min_timestamp", type: "felt" },
          { name: "max_timestamp", type: "felt" },
          { name: "calls_len", type: "felt" },
          { name: "calls", type: "ExternalCall*" },
        ],
        ExternalCall: [
          { name: "to", type: "felt" },
          { name: "selector", type: "felt" },
          { name: "calldata_len", type: "felt" },
          { name: "calldata", type: "felt*" },
        ],
      };
      const domain = {
        name: "ArgentAccount.execute_external",
        version: "1",
        chainId: chainId,
      };

      const td = {
        types: types,
        primaryType: "ExternalCalls",
        domain: domain,
        message: {
          sender: sender,
          nonce: nonce,
          min_timestamp: min_timestamp,
          max_timestamp: max_timestamp,
          calls_len: externalCalls.calls.length,
          calls: externalCalls.calls.map((call) => {
            return {
              to: call.to,
              selector: call.selector,
              calldata_len: call.calldata.length,
              calldata: call.calldata
            };
          }),
        },
      };

      const externalCallHash = typedData.getMessageHash(td, account.address);

      const foundHash = (
        await provider.callContract({
          contractAddress: account.address,
          entrypoint: "get_hash_message_external_calls",
          calldata: CallData.compile(externalCalls),
        })
      ).result[0];

      expect(foundHash).to.equal(externalCallHash);

      const signature = (await ownerSigner.signMessage(td, account.address)) as WeierstrassSignatureType;
      const signatureArray = CallData.compile([signature.r, signature.s]);

      const { transaction_hash: transferTxHash } = await deployer.execute([
        {
          contractAddress: account.address,
          entrypoint: "execute_external_calls",
          calldata: CallData.compile({ externalCalls, signatureArray }),
        },
      ]);
      const receipt = await provider.waitForTransaction(transferTxHash);
      
    });
  });
});
