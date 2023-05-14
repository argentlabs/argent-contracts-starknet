import { CallData, Signer, ec, hash, num, stark, uint256 } from "starknet";
import {
  ConcatSigner,
  declareContract,
  deployAccountV2,
  deployerAccount,
  escapeSecurityPeriod,
  expectEvent,
  getEthContract,
  increaseTime,
  provider,
  setTime,
} from "./shared";

describe("ArgentAccount: Make sure all Events are being emitted", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;

  // TODO Should we be using RANDOM recipient to not have tests cases running into each other
  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Expect AccountCreated(contract_address, owner, guardian) when deploying an account", async function () {
    const owner = "21";
    const guardian = "42";
    const constructorCalldata = CallData.compile({ owner, guardian });
    const { transaction_hash, contract_address } = await deployerAccount.deployContract({
      classHash: argentAccountClassHash,
      constructorCalldata,
    });
    const ownerAsHex = num.toHex(owner);
    const guardiangAsHex = num.toHex(guardian);
    await expectEvent(transaction_hash, {
      from_address: contract_address,
      keys: ["AccountCreated"],
      data: [contract_address, ownerAsHex, guardiangAsHex],
    });
  });

  it("Expect EscapeOwnerTriggered(active_at, new_owner) on trigger_escape_owner", async function () {
    const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
    account.signer = new Signer(guardianPrivateKey);

    const newOwner = "0x42";
    const activeAt = num.toHex(42 + escapeSecurityPeriod);
    await setTime(42);

    const { transaction_hash } = await account.execute(
      accountContract.populateTransaction.trigger_escape_owner(newOwner),
    );

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["EscapeOwnerTriggered"],
      data: [activeAt, newOwner],
    });
  });

  it("Expect OwnerEscaped(new_signer) on escape_owner", async function () {
    const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
    account.signer = new Signer(guardianPrivateKey);

    const newOwner = "0x42";
    await setTime(42);

    await account.execute(accountContract.populateTransaction.trigger_escape_owner(newOwner));
    await increaseTime(604800);

    const { transaction_hash } = await account.execute(accountContract.populateTransaction.escape_owner());

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["OwnerEscaped"],
      data: [newOwner],
    });
  });

  it("Expect EscapeGuardianTriggered(active_at, new_owner) on trigger_escape_guardian", async function () {
    const { account, accountContract, ownerPrivateKey } = await deployAccountV2(argentAccountClassHash);
    account.signer = new Signer(ownerPrivateKey);

    const newGuardian = "0x42";
    const activeAt = num.toHex(42 + escapeSecurityPeriod);
    await setTime(42);

    const { transaction_hash } = await account.execute(
      accountContract.populateTransaction.trigger_escape_guardian(newGuardian),
    );

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["EscapeGuardianTriggered"],
      data: [activeAt, newGuardian],
    });
  });

  it("Expect GuardianEscaped(new_signer) on escape_guardian", async function () {
    const { account, accountContract, ownerPrivateKey } = await deployAccountV2(argentAccountClassHash);
    account.signer = new Signer(ownerPrivateKey);
    const newGuardian = "0x42";
    await setTime(42);

    await account.execute(accountContract.populateTransaction.trigger_escape_guardian(newGuardian));
    await increaseTime(604800);

    const { transaction_hash } = await account.execute(accountContract.populateTransaction.escape_guardian());

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["GuardianEscaped"],
      data: [newGuardian],
    });
  });

  it("Expect OwnerChanged(new_signer) on change_owner", async function () {
    const { account, accountContract, ownerPrivateKey } = await deployAccountV2(argentAccountClassHash);

    const newOwnerPrivateKey = stark.randomAddress();
    const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);
    const changeOwnerSelector = hash.getSelectorFromName("change_owner");
    const chainId = await provider.getChainId();
    const contractAddress = account.address;
    const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

    const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
    const signature = ec.starkCurve.sign(msgHash, newOwnerPrivateKey);
    const { transaction_hash } = await account.execute(
      accountContract.populateTransaction.change_owner(newOwner, signature.r, signature.s),
    );

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["OwnerChanged"],
      data: [newOwner],
    });
  });

  it("Expect GuardianChanged(new_guardian) on change_guardian", async function () {
    const { account, accountContract } = await deployAccountV2(argentAccountClassHash);

    const newGuardian = "0x42";

    const { transaction_hash } = await account.execute(
      accountContract.populateTransaction.change_guardian(newGuardian),
    );

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["GuardianChanged"],
      data: [newGuardian],
    });
  });

  it("Expect GuardianBackupChanged(new_guardian_backup) on change_guardian_backup", async function () {
    const { account, accountContract } = await deployAccountV2(argentAccountClassHash);

    const newGuardianBackup = "0x42";

    const { transaction_hash } = await account.execute(
      accountContract.populateTransaction.change_guardian_backup(newGuardianBackup),
    );

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["GuardianBackupChanged"],
      data: [newGuardianBackup],
    });
  });

  it("Expect AccountUpgraded(new_implementation) on upgrade", async function () {
    const { account, accountContract } = await deployAccountV2(argentAccountClassHash);
    const argentAccountV1ClassHash = await declareContract("ArgentAccountV1");

    const { transaction_hash } = await account.execute(
      accountContract.populateTransaction.upgrade(argentAccountV1ClassHash, ["0"]),
    );

    await expectEvent(transaction_hash, {
      from_address: account.address,
      keys: ["AccountUpgraded"],
      data: [argentAccountV1ClassHash],
    });
  });

  describe("Expect EscapeCanceled()", function () {
    it("Expect on cancel_escape", async function () {
      const { account, accountContract, ownerPrivateKey, guardianPrivateKey } = await deployAccountV2(
        argentAccountClassHash,
      );
      account.signer = new Signer(ownerPrivateKey);

      await account.execute(accountContract.populateTransaction.trigger_escape_guardian("0x42"));

      account.signer = new ConcatSigner([ownerPrivateKey, guardianPrivateKey as string]);
      const { transaction_hash } = await account.execute(accountContract.populateTransaction.cancel_escape());
      await expectEvent(transaction_hash, {
        from_address: account.address,
        keys: ["EscapeCanceled"],
        data: [],
      });
    });

    it("Expect on trigger_escape_owner", async function () {
      const { account, accountContract, guardianPrivateKey } = await deployAccountV2(argentAccountClassHash);
      account.signer = new Signer(guardianPrivateKey);

      await account.execute(accountContract.populateTransaction.trigger_escape_owner("0x42"));
      const { transaction_hash } = await account.execute(
        accountContract.populateTransaction.trigger_escape_owner("0x42"),
      );
      await expectEvent(transaction_hash, {
        from_address: account.address,
        keys: ["EscapeCanceled"],
        data: [],
      });
    });

    it("Expect on trigger_escape_guardian", async function () {
      const { account, accountContract, ownerPrivateKey } = await deployAccountV2(argentAccountClassHash);
      account.signer = new Signer(ownerPrivateKey);

      await account.execute(accountContract.populateTransaction.trigger_escape_guardian("0x42"));
      const { transaction_hash } = await account.execute(
        accountContract.populateTransaction.trigger_escape_guardian("0x42"),
      );
      await expectEvent(transaction_hash, {
        from_address: account.address,
        keys: ["EscapeCanceled"],
        data: [],
      });
    });
  });

  describe("Multicall TransactionExecuted(transaction_hash, retdata)", function () {
    it("Expect ret data to contain one array with one element when making a simple transaction", async function () {
      const { account } = await deployAccountV2(argentAccountClassHash);
      const ethContract = await getEthContract();
      ethContract.connect(account);
      const recipient = "0x42";
      const amount = uint256.bnToUint256(1000);
      const retdata_total_len = num.toHex(1);
      const first_retdata_len = num.toHex(1);
      const first_retdata = num.toHex(1);
      const { transaction_hash: transferTxHash } = await account.execute(
        ethContract.populateTransaction.transfer(recipient, amount),
      );
      await expectEvent(transferTxHash, {
        from_address: account.address,
        keys: ["TransactionExecuted"],
        data: [transferTxHash, retdata_total_len, first_retdata_len, first_retdata],
      });
    });

    it("Expect retdata to contain multiple data when making a multicall transaction", async function () {
      const { account } = await deployAccountV2(argentAccountClassHash);
      const ethContract = await getEthContract();
      ethContract.connect(account);
      const recipient = "0x33";
      const amount = uint256.bnToUint256(10);
      const { balance } = await ethContract.balanceOf(recipient);
      const retdata_total_len = num.toHex(2);
      const first_retdata_len = num.toHex(1);
      const first_retdata = num.toHex(1);
      const sec_retdata_len = num.toHex(2);
      const finalBalanceLow = num.toHex(BigInt(balance.low) + BigInt(amount.low));
      const finalBalanceHigh = num.toHex(0);

      const { transaction_hash: transferTxHash } = await account.execute([
        ethContract.populateTransaction.transfer(recipient, amount),
        ethContract.populateTransaction.balanceOf(recipient),
      ]);
      await expectEvent(transferTxHash, {
        from_address: account.address,
        keys: ["TransactionExecuted"],
        data: [
          transferTxHash,
          retdata_total_len,
          first_retdata_len,
          first_retdata,
          sec_retdata_len,
          finalBalanceLow,
          finalBalanceHigh,
        ],
      });
    });
    // TODO Could add some more tests regarding multicall later
  });

  // TODO Check event NOT trigerred
});
