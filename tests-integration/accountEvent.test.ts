import { CallData, num, uint256 } from "starknet";
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
  randomKeyPair,
  setTime,
  declareFixtureContract,
  waitForTransaction,
  signChangeOwnerMessage,
  compiledSignerOption,
  signerOption,
  getEthBalance,
} from "./lib";

describe("ArgentAccount: events", function () {
  it("Expect 'AccountCreated' and 'OwnerAddded' when deploying an account", async function () {
    const owner = randomKeyPair();
    const guardian = signerOption(42n);
    const constructorCalldata = CallData.compile({ owner: owner.signerType, guardian });
    const { transaction_hash, contract_address } = await deployer.deployContract({
      classHash: await declareContract("ArgentAccount"),
      constructorCalldata,
    });

    await expectEvent(transaction_hash, {
      from_address: contract_address,
      eventName: "AccountCreated",
      additionalKeys: [owner.publicKey],
      data: ["42"],
    });

    await expectEvent(transaction_hash, {
      from_address: contract_address,
      eventName: "OwnerAdded",
      additionalKeys: [owner.publicKey],
    });
  });

  it("Expect 'EscapeOwnerTriggered(ready_at, new_owner)' on trigger_escape_owner", async function () {
    const { account, accountContract, guardian } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    const newOwner = randomKeyPair();
    const activeAt = num.toHex(42n + ESCAPE_SECURITY_PERIOD);
    await setTime(42);

    await expectEvent(() => accountContract.trigger_escape_owner(newOwner.compiledSignerType), {
      from_address: account.address,
      eventName: "EscapeOwnerTriggered",
      data: [activeAt, newOwner.publicKey],
    });
  });

  it("Expect 'OwnerEscaped', 'OwnerRemoved' and 'OwnerAdded' on escape_owner", async function () {
    const { account, accountContract, guardian, owner } = await deployAccount();
    account.signer = new ArgentSigner(guardian);

    const newOwner = randomKeyPair();
    await setTime(42);

    await accountContract.trigger_escape_owner(newOwner.compiledSignerType);
    await increaseTime(ESCAPE_SECURITY_PERIOD);
    const receipt = await waitForTransaction(await accountContract.escape_owner());
    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerEscaped",
      data: [newOwner.publicKey],
    });

    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerRemoved",
      additionalKeys: [owner.publicKey.toString()],
    });

    await expectEvent(receipt, {
      from_address: account.address,
      eventName: "OwnerAdded",
      additionalKeys: [newOwner.publicKey],
    });
  });

  it("Expect 'EscapeGuardianTriggered(ready_at, new_owner)' on trigger_escape_guardian", async function () {
    const { account, accountContract, owner } = await deployAccount();
    account.signer = new ArgentSigner(owner);

    const newGuardian = 42n;
    const activeAt = num.toHex(42n + ESCAPE_SECURITY_PERIOD);
    await setTime(42);

    await expectEvent(() => accountContract.trigger_escape_guardian(compiledSignerOption(newGuardian)), {
      from_address: account.address,
      eventName: "EscapeGuardianTriggered",
      data: [activeAt, newGuardian.toString()],
    });
  });

  it("Expect 'GuardianEscaped(new_signer)' on escape_guardian", async function () {
    const { account, accountContract, owner } = await deployAccount();
    account.signer = new ArgentSigner(owner);
    const newGuardian = 42n;
    await setTime(42);

    await accountContract.trigger_escape_guardian(compiledSignerOption(newGuardian));
    await increaseTime(ESCAPE_SECURITY_PERIOD);

    await expectEvent(() => accountContract.escape_guardian(), {
      from_address: account.address,
      eventName: "GuardianEscaped",
      data: [newGuardian.toString()],
    });
  });

  it("Expect 'OwnerChanged', 'OwnerRemoved' and 'OwnerAdded' on change_owner", async function () {
    const { accountContract, owner } = await deployAccount();

    const newOwner = randomKeyPair();
    const chainId = await provider.getChainId();

    const starknetSignature = await signChangeOwnerMessage(accountContract.address, owner.publicKey, newOwner, chainId);
    const receipt = await waitForTransaction(await accountContract.change_owner(starknetSignature));
    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "OwnerChanged",
      data: [newOwner.publicKey.toString()],
    });

    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "OwnerRemoved",
      additionalKeys: [owner.publicKey.toString()],
    });

    await expectEvent(receipt, {
      from_address: accountContract.address,
      eventName: "OwnerAdded",
      additionalKeys: [newOwner.publicKey.toString()],
    });
  });

  it("Expect 'GuardianChanged(new_guardian)' on change_guardian", async function () {
    const { accountContract } = await deployAccount();

    const newGuardian = 42n;

    await expectEvent(() => accountContract.change_guardian(compiledSignerOption(newGuardian)), {
      from_address: accountContract.address,
      eventName: "GuardianChanged",
      data: [newGuardian.toString()],
    });
  });

  it("Expect 'GuardianBackupChanged(new_guardian_backup)' on change_guardian_backup", async function () {
    const { accountContract } = await deployAccount();

    const newGuardianBackup = 42n;

    await expectEvent(() => accountContract.change_guardian_backup(compiledSignerOption(newGuardianBackup)), {
      from_address: accountContract.address,
      eventName: "GuardianBackupChanged",
      data: [newGuardianBackup.toString()],
    });
  });

  it("Expect 'AccountUpgraded(new_implementation)' on upgrade", async function () {
    const { account, accountContract } = await deployAccount();
    const argentAccountFutureClassHash = await declareFixtureContract("ArgentAccountFutureVersion");

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

      await accountContract.trigger_escape_guardian(compiledSignerOption(42n));

      account.signer = new ArgentSigner(owner, guardian);
      await expectEvent(() => accountContract.cancel_escape(), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
    });

    it("Expected on trigger_escape_owner", async function () {
      const { account, accountContract, guardian } = await deployAccount();
      account.signer = new ArgentSigner(guardian);
      const compiledSignerType = randomKeyPair().compiledSignerType;

      await accountContract.trigger_escape_owner(compiledSignerType);

      await expectEvent(() => accountContract.trigger_escape_owner(compiledSignerType), {
        from_address: account.address,
        eventName: "EscapeCanceled",
      });
    });

    it("Expected on trigger_escape_guardian", async function () {
      const { account, accountContract, owner } = await deployAccount();
      account.signer = new ArgentSigner(owner);

      await accountContract.trigger_escape_guardian(compiledSignerOption(42n));

      await expectEvent(() => accountContract.trigger_escape_guardian(compiledSignerOption(42n)), {
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
