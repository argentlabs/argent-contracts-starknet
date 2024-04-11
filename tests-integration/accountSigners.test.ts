import { Contract, uint256 } from "starknet";
import {
  ArgentAccount,
  ArgentSigner,
  declareFixtureContract,
  deployAccount,
  deployAccountWithoutGuardian,
  ensureSuccess,
  expectRevertWithErrorMessage,
  getEthContract,
  randomEip191KeyPair,
  randomEthKeyPair,
  randomSecp256r1KeyPair,
  randomStarknetKeyPair,
  randomWebauthnOwner,
  waitForTransaction,
} from "../lib";

interface Account {
  name: string;
  account: ArgentAccount;
}

describe("ArgentAccount: Signers types", function () {
  const recipient = "0xadbe1";
  const amount = uint256.bnToUint256(1);
  let ethContract: Contract;

  const accounts: Account[] = [];
  const starknetKeyPairs = [{ name: "Starknet signature", keyPair: randomStarknetKeyPair }];

  const nonStarknetKeyPairs = [
    { name: "Ethereum signature", keyPair: randomEthKeyPair },
    { name: "Secp256r1 signature", keyPair: randomSecp256r1KeyPair },
    { name: "Eip191 signature", keyPair: randomEip191KeyPair },
    { name: "Webauthn signature", keyPair: randomWebauthnOwner },
  ];

  before(async () => {
    ethContract = await getEthContract();
    await declareFixtureContract("Sha256Cairo0");

    for (const { name, keyPair } of [...starknetKeyPairs, ...nonStarknetKeyPairs]) {
      const { account: withGuardian } = await deployAccount({ owner: keyPair() });
      accounts.push({ name, account: withGuardian });
      const { account: withoutGuardian } = await deployAccountWithoutGuardian({ owner: keyPair() });
      accounts.push({ name: name + " (without guardian)", account: withoutGuardian });
    }
  });

  it("Waiting accounts to be filled", function () {
    describe("Simple transfer", function () {
      for (const { name, account } of accounts) {
        it(`Using "${name}"`, async function () {
          ethContract.connect(account);
          await ensureSuccess(await waitForTransaction(await ethContract.transfer(recipient, amount)));
        });
      }
    });
  });

  for (const { name, keyPair } of nonStarknetKeyPairs) {
    it(`Expect 'argent/invalid-guardian-type' when deploying with a wrong guardian "${name}"`, async function () {
      await expectRevertWithErrorMessage("argent/invalid-guardian-type", async () => {
        const { transactionHash } = await deployAccount({ guardian: keyPair() });
        return { transaction_hash: transactionHash };
      });
    });

    it(`Expect 'argent/invalid-guardian-type' on trigger_escape_guardian with "${name}"`, async function () {
      const { accountContract, account, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);
      await expectRevertWithErrorMessage("argent/invalid-guardian-type", () =>
        accountContract.trigger_escape_guardian(keyPair().compiledSignerAsOption),
      );
    });
  }
});
