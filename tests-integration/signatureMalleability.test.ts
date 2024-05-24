import { randomBytes } from "crypto";
import { ContractWithClass, EthKeyPair, Secp256r1KeyPair, manager, randomStarknetKeyPair } from "../lib";

describe("Signature malleability", function () {
  const iterations = 1000;
  let signatureVerifier: ContractWithClass;
  this.beforeAll(async function () {
    signatureVerifier = await manager.deployContract("SignatureVerifier");
  });

  it("Secp256R1", async function () {
    for (let i = 0; i < iterations; i++) {
      const privateKey = BigInt("0x" + randomBytes(32).toString("hex"));
      const msgHash = randomStarknetKeyPair().privateKey;
      const signer = new Secp256r1KeyPair(privateKey, true /* allowLowS */);
      const signature = await signer.signRaw(msgHash);
      await signatureVerifier.call("assert_valid_signature", [msgHash, signature]);
    }
  });

  it("Secp256K1", async function () {
    for (let i = 0; i < iterations; i++) {
      const privateKey = BigInt("0x" + randomBytes(32).toString("hex"));
      const msgHash = randomStarknetKeyPair().privateKey;
      const signer = new EthKeyPair(privateKey, true /* allowLowS */);
      const signature = await signer.signRaw(msgHash);
      await signatureVerifier.call("assert_valid_signature", [msgHash, signature]);
    }
  });
});
