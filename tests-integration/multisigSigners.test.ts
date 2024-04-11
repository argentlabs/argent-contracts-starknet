import { uint256 } from "starknet";
import {
  ArgentAccount,
  declareFixtureContract,
  deployMultisig,
  ensureSuccess,
  getEthContract,
  randomEip191KeyPair,
  randomEthKeyPair,
  randomSecp256r1KeyPair,
  randomStarknetKeyPair,
  randomWebauthnOwner,
  sortByGuid,
  waitForTransaction,
} from "../lib";

// For some reason I have to put this out of the describe...
// Otherwise the accounts array is empty
interface Account {
  name: string;
  account: ArgentAccount;
}

const accounts: Account[] = [];
const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);
const ethContract = await getEthContract();
await declareFixtureContract("Sha256Cairo0");

const keyPairs = [
  { name: "Starknet signature", keyPair: randomStarknetKeyPair },
  { name: "Ethereum signature", keyPair: randomEthKeyPair },
  { name: "Secp256r1 signature", keyPair: randomSecp256r1KeyPair },
  { name: "Eip191 signature", keyPair: randomEip191KeyPair },
  { name: "Webauthn signature", keyPair: randomWebauthnOwner },
];

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

describe("Multisig: testing all signers", function () {
  for (const { name, account } of accounts) {
    it(`Testing "${name}"`, async function () {
      ethContract.connect(account);
      await ensureSuccess(await waitForTransaction(await ethContract.transfer(recipient, amount)));
    });
  }
});
