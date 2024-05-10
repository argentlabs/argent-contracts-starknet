import { expect } from "chai";
import { CallData, hash } from "starknet";
import {
  deployMultisig1_1,
  ensureSuccess,
  expectRevertWithErrorMessage,
  manager,
  randomStarknetKeyPair,
  waitForTransaction,
} from "../lib";

const initialTime = 100;

async function buildFixture() {
  const { accountContract, keys: originalKeys, account: originalAccount } = await deployMultisig1_1();
  const { account: guardianAccount } = await deployMultisig1_1();
  const originalSigner = originalKeys[0];
  const newSigner = randomStarknetKeyPair();
  await accountContract.toggle_escape(
    CallData.compile({
      is_enabled: true,
      security_period: 10 * 60,
      expiry_period: 10 * 60,
      guardian: guardianAccount.address,
    }),
  );
  const replaceSignerCall = CallData.compile({
    selector: hash.getSelectorFromName("replace_signer"),
    calldata: CallData.compile({
      signerToRemove: originalSigner.signer,
      signerToAdd: newSigner.signer,
    }),
  });
  return { accountContract, originalSigner, newSigner, guardianAccount, replaceSignerCall, originalAccount };
}

describe("ArgentMultisig Recovery", function () {
  it(`Should be able to perform recovery on multisig`, async function () {
    const { accountContract, originalSigner, newSigner, guardianAccount, replaceSignerCall } = await buildFixture();
    const { account: thirdPartyAccount } = await deployMultisig1_1();
    await manager.setTime(initialTime);
    accountContract.connect(guardianAccount);
    await accountContract.trigger_escape(replaceSignerCall);

    await manager.setTime(initialTime + 10 * 60);
    accountContract.connect(thirdPartyAccount);
    await ensureSuccess(await waitForTransaction(await accountContract.execute_escape(replaceSignerCall)));
    accountContract.is_signer(originalSigner.compiledSigner).should.eventually.equal(false);
    accountContract.is_signer(newSigner.compiledSigner).should.eventually.equal(true);

    const { "0": escape, "1": status } = await accountContract.get_escape();
    expect(escape.ready_at).to.equal(0n);
    expect(escape.call_hash).to.equal(0n);
    expect(status.variant.None).to.eql({});
  });

  it(`Shouldn't be possible to call 'execute_escape' when calling 'trigger_escape'`, async function () {
    const { accountContract, guardianAccount, replaceSignerCall, originalAccount } = await buildFixture();
    await provider.setTime(initialTime);
    accountContract.connect(guardianAccount);
    await accountContract.trigger_escape(replaceSignerCall);

    await provider.setTime(initialTime + 15);
    accountContract.connect(originalAccount);
    await expectRevertWithErrorMessage("ReentrancyGuard: reentrant call", () =>
      accountContract.execute_escape(replaceSignerCall),
    );
  });

  it(`Shouldn't be possible to call 'execute_escape' when calling 'trigger_escape'`, async function () {
    const { accountContract, guardianAccount } = await buildFixture();
    await provider.setTime(initialTime);
    accountContract.connect(guardianAccount);
    const replaceSignerCall = CallData.compile({
      selector: hash.getSelectorFromName("execute_escape"),
      calldata: [],
    });
    await expectRevertWithErrorMessage("argent/invalid-selector", () =>
      accountContract.trigger_escape(replaceSignerCall),
    );
  });

  it(`Escape should fail outside time window`, async function () {
    const { accountContract, guardianAccount, replaceSignerCall } = await buildFixture();
    await manager.setTime(initialTime);
    accountContract.connect(guardianAccount);
    await accountContract.trigger_escape(replaceSignerCall);

    await manager.setTime(initialTime + 1);
    await expectRevertWithErrorMessage("argent/invalid-escape", () =>
      accountContract.execute_escape(replaceSignerCall),
    );
  });
});
