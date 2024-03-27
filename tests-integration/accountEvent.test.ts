import { CallData, uint256 } from "starknet";
import {
  ArgentSigner,
  ESCAPE_SECURITY_PERIOD,
  declareContract,
  deployAccount,
  deployer,
  expectEvent,
  getEthContract,
  increaseTime,
  provider,
  randomStarknetKeyPair,
  setTime,
  declareFixtureContract,
  waitForTransaction,
  signChangeOwnerMessage,
  getEthBalance,
} from "./lib";

describe("ArgentAccount: events", function () {
  const initialTime = 24 * 60 * 60;
  it("Expect 'AccountCreated' when deploying an account", async function () {
    const owner = randomStarknetKeyPair();
    const guardian = randomStarknetKeyPair();
    const constructorCalldata = CallData.compile({ owner: owner.signer, guardian: guardian.signerAsOption });
    const { transaction_hash, contract_address } = await deployer.deployContract({
      classHash: await declareContract("ArgentAccount"),
      constructorCalldata,
    });

    await expectEvent(transaction_hash, {
      from_address: contract_address,
      eventName: "AccountCreated",
      additionalKeys: [owner.storedValue.toString()],
      data: [guardian.storedValue.toString()],
    });

    await expectEvent(transaction_hash, {
      from_address: contract_address,
      eventName: "AccountCreatedGuid",
      additionalKeys: [owner.guid.toString()],
      data: [guardian.guid.toString()],
    });
  });

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

  it("Expect 'AccountUpgraded(new_implementation)' on upgrade", async function () {
    const { account, accountContract } = await deployAccount();
    const argentAccountFutureClassHash = await declareContract("MockFutureArgentAccount");

    await expectEvent(
      () => account.execute(accountContract.populateTransaction.upgrade(argentAccountFutureClassHash, ["0"])),
      {
        from_address: account.address,
        eventName: "AccountUpgraded",
        data: [argentAccountFutureClassHash],
      },
    );
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

  describe("Expect 'TransactionExecuted(transaction_hash, retdata)' on multicall", function () {
    it("Expect ret data to contain one array with one element when making a simple transaction", async function () {
      const { account } = await deployAccount();
      const ethContract = await getEthContract();
      ethContract.connect(account);

      const recipient = "42";
      const amount = uint256.bnToUint256(1000);
      const first_retdata = [1];
      const { transaction_hash } = await ethContract.transfer(recipient, amount);
      await expectEvent(transaction_hash, {
        from_address: account.address,
        eventName: "TransactionExecuted",
        additionalKeys: [transaction_hash],
        data: CallData.compile([[first_retdata]]),
      });
    });

    it("Expect retdata to contain multiple data when making a multicall transaction", async function () {
      const { account } = await deployAccount();
      const ethContract = await getEthContract();
      ethContract.connect(account);

      const recipient = "0x33";
      const amount = 10n;

      const balance = await getEthBalance(recipient);

      const finalBalance = uint256.bnToUint256(balance + amount);
      const firstReturn = [1];
      const secondReturn = [finalBalance.low, finalBalance.high];

      const { transaction_hash } = await account.execute([
        ethContract.populateTransaction.transfer(recipient, uint256.bnToUint256(amount)),
        ethContract.populateTransaction.balanceOf(recipient),
      ]);
      await expectEvent(transaction_hash, {
        from_address: account.address,
        eventName: "TransactionExecuted",
        additionalKeys: [transaction_hash],
        data: CallData.compile([[firstReturn, secondReturn]]),
      });
    });
    // TODO Could add some more tests regarding multicall later
  });
});
