import {
  ArgentSigner,
  ESCAPE_SECURITY_PERIOD,
  deployAccount,
  expectEvent,
  increaseTime,
  provider,
  randomStarknetKeyPair,
  setTime,
  signChangeOwnerMessage,
  waitForTransaction,
} from "./lib";

describe("ArgentAccount: events", function () {
  const initialTime = 24 * 60 * 60;

  it("Expect 'EscapeOwnerTriggered(ready_at, new_owner)' on trigger_escape_owner", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    const newOwner = randomStarknetKeyPair();
    await setTime(initialTime);

    const activeAt = BigInt(initialTime) + ESCAPE_SECURITY_PERIOD;
    const receipt = await waitForTransaction(await accountContract.trigger_escape_owner(newOwner.compiledSigner));

    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "EscapeOwnerTriggeredGuid",
      data: [activeAt.toString(), newOwner.guid.toString()],
    });
  });

  it("Expect 'OwnerEscaped' on escape_owner", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    const newOwner = randomStarknetKeyPair();
    await setTime(initialTime);

    await accountContract.trigger_escape_owner(newOwner.compiledSigner);
    await increaseTime(ESCAPE_SECURITY_PERIOD);
    const receipt = await waitForTransaction(await accountContract.escape_owner());
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerEscapedGuid",
      data: [newOwner.guid.toString()],
    });
  });

  it("Expect 'EscapeGuardianTriggered(ready_at, new_owner)' on trigger_escape_guardian", async function () {
    const { account, accountContract, owner } = await deployAccount();
    account.signer = new ArgentSigner(owner);

    const newGuardian = randomStarknetKeyPair();
    await setTime(initialTime);
    const receipt = await waitForTransaction(
      await accountContract.trigger_escape_guardian(newGuardian.compiledSignerAsOption),
    );

    const activeAt = BigInt(initialTime) + ESCAPE_SECURITY_PERIOD;
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "EscapeGuardianTriggeredGuid",
      data: [activeAt.toString(), newGuardian.guid.toString()],
    });
  });

  it("Expect 'GuardianEscaped(new_signer)' on escape_guardian", async function () {
    const { account, accountContract, owner } = await deployAccount();
    account.signer = new ArgentSigner(owner);
    const newGuardian = randomStarknetKeyPair();
    await setTime(initialTime);

    await accountContract.trigger_escape_guardian(newGuardian.compiledSignerAsOption);
    await increaseTime(ESCAPE_SECURITY_PERIOD);
    const receipt = await waitForTransaction(await accountContract.escape_guardian());
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "GuardianEscapedGuid",
      data: [newGuardian.guid.toString()],
    });
  });

  it("Expect 'OwnerChanged' on change_owner", async function () {
    const { accountContract, owner } = await deployAccount();

    const newOwner = randomStarknetKeyPair();
    const chainId = await provider.getChainId();

    const starknetSignature = await signChangeOwnerMessage(accountContract.address, owner.guid, newOwner, chainId);
    const receipt = await waitForTransaction(await accountContract.change_owner(starknetSignature));
    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "OwnerChanged",
      data: [newOwner.storedValue.toString()],
    });
    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "OwnerChangedGuid",
      data: [newOwner.guid.toString()],
    });
  });

  it("Expect 'GuardianChanged(new_guardian)' on change_guardian", async function () {
    const { accountContract } = await deployAccount();

    const newGuardian = randomStarknetKeyPair();
    const receipt = await waitForTransaction(await accountContract.change_guardian(newGuardian.compiledSignerAsOption));

    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "GuardianChanged",
      data: [newGuardian.storedValue.toString()],
    });
    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "GuardianChangedGuid",
      data: [newGuardian.guid.toString()],
    });
  });

  it("Expect 'GuardianBackupChanged(new_guardian_backup)' on change_guardian_backup", async function () {
    const { accountContract } = await deployAccount();

    const newGuardianBackup = randomStarknetKeyPair();
    const receipt = await waitForTransaction(
      await accountContract.change_guardian_backup(newGuardianBackup.compiledSignerAsOption),
    );

    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "GuardianBackupChanged",
      data: [newGuardianBackup.storedValue.toString()],
    });
    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "GuardianBackupChangedGuid",
      data: [newGuardianBackup.guid.toString()],
    });
  });

  describe("Expect 'EscapeCanceled()'", function () {
    it("Expected on cancel_escape", async function () {
      const { account, accountContract, owner, guardian } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await accountContract.trigger_escape_guardian(randomStarknetKeyPair().compiledSignerAsOption);

      account.signer = new ArgentSigner(owner, guardian);
      await expectEvent(() => accountContract.cancel_escape(), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
    });

    it("Expected on trigger_escape_owner", async function () {
      const { account, accountContract, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);
      const { compiledSigner } = randomStarknetKeyPair();

      setTime(initialTime);
      await accountContract.trigger_escape_owner(compiledSigner);

      // increased time to prevent escape too recent error
      setTime(initialTime + 1 + 12 * 60 * 60 * 2);
      await expectEvent(() => accountContract.trigger_escape_owner(compiledSigner), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
    });

    it("Expected on trigger_escape_guardian", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      setTime(initialTime);
      await accountContract.trigger_escape_guardian(randomStarknetKeyPair().compiledSignerAsOption);

      // increased time to prevent escape too recent error
      setTime(initialTime + 1 + 12 * 60 * 60 * 2);
      await expectEvent(() => accountContract.trigger_escape_guardian(randomStarknetKeyPair().compiledSignerAsOption), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
    });
  });
});
