import { Contract, uint256 } from "starknet";
import {
  ArgentAccount,
  deployMultisig,
  manager,
  randomEip191KeyPair,
  randomEthKeyPair,
  randomSecp256r1KeyPair,
  randomStarknetKeyPair,
  randomWebauthnOwner,
  sortByGuid,
} from "../lib";

interface Account {
  name: string;
  account: ArgentAccount;
}

describe("Multisig: Signers types", function () {
  const accounts: Account[] = [];
  const recipient = "0xadbe1";
  const amount = uint256.bnToUint256(1);
  let ethContract: Contract;
  const keyPairs = [
    { name: "Starknet signature", keyPair: randomStarknetKeyPair },
    { name: "Ethereum signature", keyPair: randomEthKeyPair },
    { name: "Secp256r1 signature", keyPair: randomSecp256r1KeyPair },
    { name: "Eip191 signature", keyPair: randomEip191KeyPair },
    { name: "Webauthn signature", keyPair: randomWebauthnOwner },
  ];

  before(async () => {
    ethContract = await manager.tokens.ethContract();
    await manager.declareFixtureContract("Sha256Cairo0");

    for (const { name, keyPair } of keyPairs) {
      const { account: oneSigner } = await deployMultisig({ threshold: 1, keys: [keyPair()] });
      accounts.push({ name: "1 " + name, account: oneSigner });

      const keys = [...Array(5)].map(() => keyPair());
      sortByGuid(keys);
      const { account: fiveSigners } = await deployMultisig({ threshold: 5, keys });
      accounts.push({ name: "5 " + name, account: fiveSigners });
    }

    const allKeys = keyPairs.map((k) => k.keyPair());
    sortByGuid(allKeys);
    const { account } = await deployMultisig({ threshold: 5, keys: allKeys });
    accounts.push({ name: "One of each", account });
  });

  it("Waiting accounts to be filled", function () {
    describe("Simple transfer", function () {
      for (const { name, account } of accounts) {
        it(`Using "${name}"`, async function () {
          ethContract.connect(account);
          await manager.ensureSuccess(async () => ethContract.transfer(recipient, amount));
        });
      }
    });
  });
});
