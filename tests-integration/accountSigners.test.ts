import { uint256 } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  EthKeyPair,
  Secp256r1KeyPair,
  StarknetKeyPair,
  WebauthnOwner,
  declareFixtureContract,
  deployAccount,
  deployAccountWithoutGuardian,
  ensureSuccess,
  expectRevertWithErrorMessage,
  getEthContract,
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

const starknetKeyPairs = [{ name: "Starknet signature", keyPair: new StarknetKeyPair() }];

const nonStarknetKeyPairs = [
  { name: "Ethereum signature", keyPair: new EthKeyPair() },
  { name: "Secp256r1 signature", keyPair: new Secp256r1KeyPair() },
  { name: "Eip191 signature", keyPair: new Secp256r1KeyPair() },
  { name: "Webauthn signature", keyPair: new WebauthnOwner() },
];

for (const { name, keyPair } of [...starknetKeyPairs, ...nonStarknetKeyPairs]) {
  const { account: withGuardian } = await deployAccount({ owner: keyPair });
  accounts.push({ name, account: withGuardian });
  const { account: withoutGuardian } = await deployAccountWithoutGuardian({ owner: keyPair });
  accounts.push({ name: name + " (without guardian)", account: withoutGuardian });
}

describe("ArgentAccount: testing all signers", function () {
  for (const { name, account } of accounts) {
    it(`Testing "${name}"`, async function () {
      ethContract.connect(account);
      await ensureSuccess(await waitForTransaction(await ethContract.transfer(recipient, amount)));
    });
  }

  for (const { name, keyPair } of nonStarknetKeyPairs) {
    it(`Deploying with a wrong guardian "${name}"`, async function () {
      await expectRevertWithErrorMessage("argent/invalid-guardian-type", async () => {
        const { transactionHash } = await deployAccount({ guardian: keyPair });
        return { transaction_hash: transactionHash };
      });
    });

    it(`trigger_escape_guardian "${name}"`, async function () {
      const { accountContract, account, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);
      await expectRevertWithErrorMessage("argent/invalid-guardian-type", () =>
        accountContract.trigger_escape_guardian(keyPair.compiledSignerAsOption),
      );
    });
  }
});
