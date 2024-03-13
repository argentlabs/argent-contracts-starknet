import { CallData, hash } from "starknet";
import { deployMultisig1_1, setTime, ensureSuccess, waitForTransaction, randomStarknetKeyPair } from "./lib";
import { expect } from "chai";

describe("ArgentMultisig Recovery", function () {
  it(`Should be able to perform recovery on multisig`, async function () {
    const { accountContract, keys: originalKeys } = await deployMultisig1_1();
    const { account: guardianAccount, keys: guardianKeys } = await deployMultisig1_1();
    const { account: thirdPartyAccount } = await deployMultisig1_1();

    const originalSigner = originalKeys[0];
    const newSigner = randomStarknetKeyPair();
    await setTime(100);
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
    accountContract.connect(guardianAccount);
    await accountContract.trigger_escape(replaceSignerCall);

    await setTime(115);
    accountContract.connect(thirdPartyAccount);
    await ensureSuccess(await waitForTransaction(await accountContract.execute_escape(replaceSignerCall)));
    accountContract.is_signer(originalSigner.compiledSigner).should.eventually.equal(false);
    accountContract.is_signer(newSigner.compiledSigner).should.eventually.equal(true);

    const { "0": escape, "1": status } = await accountContract.get_escape();
    expect(escape.ready_at).to.equal(0n);
    expect(escape.call_hash).to.equal(0n);
    expect(status.variant.None).to.eql({});
  });
});
