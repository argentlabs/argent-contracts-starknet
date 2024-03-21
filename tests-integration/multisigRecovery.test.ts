import { CallData, hash } from "starknet";
import {
  deployMultisig1_1,
  setTime,
  ensureSuccess,
  waitForTransaction,
  randomStarknetKeyPair,
  expectRevertWithErrorMessage,
} from "./lib";
import { expect } from "chai";

const initialTime = 100;

async function buildFixture() {
  const { accountContract, keys: originalKeys } = await deployMultisig1_1();
  const { account: guardianAccount } = await deployMultisig1_1();
  const originalSigner = originalKeys[0];
  const newSigner = randomStarknetKeyPair();
  await accountContract.toggle_escape(
    true, // is_enabled,
    10, // security_period
    10, // expiry_period
    guardianAccount.address, // guardian
  );
  const replaceSignerCall = CallData.compile({
    selector: hash.getSelectorFromName("replace_signer"),
    calldata: CallData.compile({
      signerToRemove: originalSigner.signer,
      signerToAdd: newSigner.signer,
    }),
  });
  return { accountContract, originalSigner, newSigner, guardianAccount, replaceSignerCall };
}

describe("ArgentMultisig Recovery", function () {
  it(`Should be able to perform recovery on multisig`, async function () {
    const { accountContract, originalSigner, newSigner, guardianAccount, replaceSignerCall } = await buildFixture();
    const { account: thirdPartyAccount } = await deployMultisig1_1();
    await setTime(initialTime);
    accountContract.connect(guardianAccount);
    await accountContract.trigger_escape(replaceSignerCall);

    await setTime(initialTime + 15);
    accountContract.connect(thirdPartyAccount);
    await ensureSuccess(await waitForTransaction(await accountContract.execute_escape(replaceSignerCall)));
    accountContract.is_signer(originalSigner.compiledSigner).should.eventually.equal(false);
    accountContract.is_signer(newSigner.compiledSigner).should.eventually.equal(true);

    const { "0": escape, "1": status } = await accountContract.get_escape();
    expect(escape.ready_at).to.equal(0n);
    expect(escape.call_hash).to.equal(0n);
    expect(status.variant.None).to.eql({});
  });

  it(`Escape should fail outside time window`, async function () {
    const { accountContract, guardianAccount, replaceSignerCall } = await buildFixture();
    await setTime(initialTime);
    accountContract.connect(guardianAccount);
    await accountContract.trigger_escape(replaceSignerCall);

    await setTime(initialTime + 1);
    await expectRevertWithErrorMessage("argent/invalid-escape", () =>
      accountContract.execute_escape(replaceSignerCall),
    );
  });
});
