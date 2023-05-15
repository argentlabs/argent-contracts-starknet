import { expect } from "chai";
import { CallData, Signer, ec, hash, num, stark, uint256 } from "starknet";
import {
  ArgentSigner,
  ConcatSigner,
  declareContract,
  deployAccount,
  deployerAccount,
  expectEvent,
  expectRevertWithErrorMessage,
  getEthContract,
  increaseTime,
  loadContract,
  provider,
  setTime,
} from "./shared";

describe("Test contract: ArgentAccount", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;
  // let testDapp: Contract;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
    // const testDappClassHash = await declareContract("TestDapp");
    // testDapp = await deployAndLoadContract(testDappClassHash);
  });

  beforeEach(async () => {
    // TODO When everything is more clean, we could deploy a new funded cairo1 account and use that one to do all the logic
  });

  describe("Example tests", function () {
    it("Deploy a contract without guardian", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account.address);
      const result = await accountContract.get_guardian();
      expect(result).to.equal(0n);
    });

    it("Deploy a contract with guardian", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);
      const result = await accountContract.get_guardian();
      const guardianPublicKey = ec.starkCurve.getStarkKey(guardianPrivateKey);
      expect(result).to.equal(BigInt(guardianPublicKey));
    });

    it("Expect an error when owner is zero", async function () {
      await expectRevertWithErrorMessage("argent/null-owner", async () => {
        await deployerAccount.deployContract({
          classHash: argentAccountClassHash,
          constructorCalldata: CallData.compile({ owner: 0, guardian: 12 }),
        });
      });
    });

    it("Expect event AccountCreated(contract_address, owner, guardian) to be triggered when deploying a contract", async function () {
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

    it("Should be possible to send eth with a Cairo1 account", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const recipient = "0x42";
      const amount = uint256.bnToUint256(1000);
      const ethContract = await getEthContract();
      const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipientInitialBalance } = await ethContract.balanceOf(recipient);
      ethContract.connect(account);
      // TODO it should be possible to do this at some point
      // await ethContract.transfer(recipient, amount);
      const { transaction_hash: transferTxHash } = await account.execute(
        ethContract.populateTransaction.transfer(recipient, amount),
      );

      await account.waitForTransaction(transferTxHash);
      const { balance: senderFinalBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipientFinalBalance } = await ethContract.balanceOf(recipient);
      // Before amount should be higher than (after + transfer) amount due to fee
      expect(uint256.uint256ToBN(senderInitialBalance) + 1000n > uint256.uint256ToBN(senderFinalBalance)).to.be.true;
      expect(uint256.uint256ToBN(recipientInitialBalance) + 1000n).to.equal(uint256.uint256ToBN(recipientFinalBalance));
    });

    it("Should be possible to send eth with a Cairo1 account using a multicall", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const recipient1 = "0x42";
      const amount1 = uint256.bnToUint256(1000);
      const recipient2 = "0x43";
      const amount2 = uint256.bnToUint256(42000);
      const ethContract = await getEthContract();

      const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipient1InitialBalance } = await ethContract.balanceOf(recipient1);
      const { balance: recipient2InitialBalance } = await ethContract.balanceOf(recipient2);

      const { transaction_hash: transferTxHash } = await account.execute([
        ethContract.populateTransaction.transfer(recipient1, amount1),
        ethContract.populateTransaction.transfer(recipient2, amount2),
      ]);
      await account.waitForTransaction(transferTxHash);

      const { balance: senderFinalBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipient1FinalBalance } = await ethContract.balanceOf(recipient1);
      const { balance: recipient2FinalBalance } = await ethContract.balanceOf(recipient2);
      expect(senderInitialBalance.high).to.equal(senderFinalBalance.high);
      // Before amount should be higher than (after + transfer) amount due to fee
      expect(Number(senderInitialBalance.low)).to.be.greaterThan(Number(senderFinalBalance.low) + 1000 + 42000);
      expect(uint256.uint256ToBN(recipient1InitialBalance) + 1000n).to.equal(
        uint256.uint256ToBN(recipient1FinalBalance),
      );
      expect(uint256.uint256ToBN(recipient2InitialBalance) + 42000n).to.equal(
        uint256.uint256ToBN(recipient2FinalBalance),
      );
    });

    it("Expect an error when a multicall contains a Call referencing the account itself", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account.address);
      const ethContract = await getEthContract();

      await expectRevertWithErrorMessage("argent/no-multicall-to-self", async () => {
        const recipient = "0x42";
        const amount = uint256.bnToUint256(1000);
        const newOwner = "0x69";
        await account.execute([
          ethContract.populateTransaction.transfer(recipient, amount),
          accountContract.populateTransaction.trigger_escape_owner(newOwner),
        ]);
      });
    });

    it("Should be possible to trigger escape guardian by the owner alone", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);
      const guardianPrivateKey = stark.randomAddress();
      const guardianPublicKey = ec.starkCurve.getStarkKey(guardianPrivateKey);
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);

      const accountContract = await loadContract(account.address);
      const owner = await accountContract.get_owner();
      expect(owner).to.equal(BigInt(ownerPublicKey));
      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(BigInt(guardianPublicKey));

      await setTime(42);
      accountContract.connect(account);

      await account.execute(accountContract.populateTransaction.trigger_escape_guardian("0x43"));

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(1n);
      expect(escape.active_at).to.equal(42n + 604800n);
    });

    it("Should be possible to escape a guardian by the owner alone", async function () {
      const privateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, privateKey, "0x42");
      const accountContract = await loadContract(account.address);

      await setTime(42);
      await account.execute(accountContract.populateTransaction.trigger_escape_guardian("0x43"));
      await increaseTime(604800);

      await account.execute(accountContract.populateTransaction.escape_guardian());

      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(0n);
      expect(escape.active_at).to.equal(0n);
      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(BigInt("0x43"));
    });

    it("Should use GUARDIAN signature when escaping owner", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      account.signer = new Signer(guardianPrivateKey);
      await account.execute(accountContract.populateTransaction.trigger_escape_owner("0x42"));

      await setTime(42);
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(2n);
      expect(Number(escape.active_at)).to.be.greaterThanOrEqual(42 + 604800);
    });

    it("Should use signature from BOTH OWNER and GUARDIAN when there is a GUARDIAN", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      const guardianBackupBefore = await accountContract.get_guardian_backup();
      expect(guardianBackupBefore).to.equal(0n);
      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      await account.execute(accountContract.populateTransaction.change_guardian_backup("0x42"));

      const guardianBackupAfter = await accountContract.get_guardian_backup();
      expect(guardianBackupAfter).to.equal(BigInt("0x42"));
    });

    it("Should sign messages from OWNER and BACKUP_GUARDIAN when there is a GUARDIAN and a BACKUP", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const guardianBackupPrivateKey = stark.randomAddress();
      const guardianBackupPublicKey = ec.starkCurve.getStarkKey(guardianBackupPrivateKey);
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      const guardianBackupBefore = await accountContract.get_guardian_backup();
      expect(guardianBackupBefore).to.equal(0n);

      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      await account.execute(accountContract.populateTransaction.change_guardian_backup(guardianBackupPublicKey));

      const guardianBackupAfter = await accountContract.get_guardian_backup();
      expect(guardianBackupAfter).to.equal(BigInt(guardianBackupPublicKey));

      account.signer = new ArgentSigner(ownerPrivateKey, guardianBackupPrivateKey);
      await account.execute(accountContract.populateTransaction.change_guardian("0x42"));

      const guardianAfter = await accountContract.get_guardian();
      expect(guardianAfter).to.equal(BigInt("0x42"));
    });

    it("Should throw an error when signing a transaction with OWNER, GUARDIAN and BACKUP", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const guardianBackupPrivateKey = stark.randomAddress();
      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
      const accountContract = await loadContract(account.address);

      account.signer = new ConcatSigner([ownerPrivateKey, guardianPrivateKey, guardianBackupPrivateKey]);

      await expectRevertWithErrorMessage("argent/invalid-signature-length", async () => {
        await account.execute(accountContract.populateTransaction.change_guardian("0x42"));
      });
    });

    it("Should throw an error the signature given to change owner is invalid", async function () {
      const account = await deployAccount(argentAccountClassHash);
      const accountContract = await loadContract(account.address);
      const newOwnerPrivateKey = stark.randomAddress();
      const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);

      await expectRevertWithErrorMessage("argent/invalid-owner-sig", async () => {
        await account.execute(accountContract.populateTransaction.change_owner(newOwner, "0x12", "0x42"));
      });
    });

    it("Should throw an error the signature given to change owner is invalid", async function () {
      const ownerPrivateKey = stark.randomAddress();

      const account = await deployAccount(argentAccountClassHash, ownerPrivateKey);
      const accountContract = await loadContract(account.address);
      const newOwnerPrivateKey = stark.randomAddress();
      const newOwner = ec.starkCurve.getStarkKey(newOwnerPrivateKey);
      const changeOwnerSelector = hash.getSelectorFromName("change_owner");
      const chainId = await provider.getChainId();
      const contractAddress = account.address;
      const ownerPublicKey = ec.starkCurve.getStarkKey(ownerPrivateKey);

      const msgHash = hash.computeHashOnElements([changeOwnerSelector, chainId, contractAddress, ownerPublicKey]);
      const signature = ec.starkCurve.sign(msgHash, newOwnerPrivateKey);
      await account.execute(accountContract.populateTransaction.change_owner(newOwner, signature.r, signature.s));

      const owner_result = await accountContract.get_owner();
      expect(owner_result).to.equal(BigInt(newOwner));
    });
  });

  xit("Should be posssible to deploy an argent account version 0.3.0", async function () {
    // await deployAccount(argentAccountClassHash);
    // TODO Impossible atm needs not (yet) deployAccount doesn't support yet cairo1 call structure
  });
});
