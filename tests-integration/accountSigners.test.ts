import { Contract, uint256 } from "starknet";
import {
  ArgentAccount,
  deployAccount,
  deployAccountWithoutGuardians,
  manager,
  randomEip191KeyPair,
  randomEthKeyPair,
  randomSecp256r1KeyPair,
  randomStarknetKeyPair,
  randomWebauthnCairo0Owner,
  randomWebauthnOwner,
} from "../lib";

interface Account {
  name: string;
  account: ArgentAccount;
}

describe("ArgentAccount: Signer types", function () {
  const recipient = "0xadbe1";
  const amount = uint256.bnToUint256(1);
  let ethContract: Contract;

  const accounts: Account[] = [];
  const signerTypes = [
    { name: "Starknet signature", keyPair: randomStarknetKeyPair },
    { name: "Ethereum signature", keyPair: randomEthKeyPair },
    { name: "Secp256r1 signature", keyPair: randomSecp256r1KeyPair },
    { name: "Eip191 signature", keyPair: randomEip191KeyPair },
    { name: "Webauthn signature", keyPair: randomWebauthnOwner },
    { name: "Webauthn signature (cairo0)", keyPair: randomWebauthnCairo0Owner },
  ];

  before(async () => {
    ethContract = await manager.tokens.ethContract();
    await manager.declareFixtureContract("Sha256Cairo0");

    for (const { name, keyPair } of signerTypes) {
      const { account: withGuardian } = await deployAccount({ owner: keyPair() });
      accounts.push({ name, account: withGuardian });
      const { account: withoutGuardian } = await deployAccountWithoutGuardians({ owner: keyPair() });
      accounts.push({ name: name + " (without guardian)", account: withoutGuardian });
    }
  });

  it("Waiting accounts to be filled", function () {
    describe("Simple transfer", function () {
      for (const { name, account } of accounts) {
        it(`Using "${name}"`, async function () {
          ethContract.connect(account);
          await manager.ensureSuccess(ethContract.transfer(recipient, amount));
        });
      }
    });
  });
});
