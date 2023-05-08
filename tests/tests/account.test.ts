import { expect } from "chai";
import { CallData, Signer, ec, num, stark, uint256 } from "starknet";
import { deployAccount, deployCairo1AccountWithGuardian, getCairo1Account } from "./shared/account";
import {
  account,
  declareContract,
  deployAndLoadAccountContract,
  expectEvent,
  expectRevertWithErrorMessage,
  loadContract,
} from "./shared/lib";

import { ArgentSigner } from "./shared/argentSigner";
import { ethAddress, getEthContract } from "./shared/constants";
import { increaseTime, setTime } from "./shared/devnetInteraction";

describe("Test contract: ArgentAccount", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;
  let oldArgentAccountClassHash: string;
  let proxyClassHash: string;
  // let testDapp: Contract;

  before(async () => {
    console.log("\tSetup ongoing...");
    argentAccountClassHash = await declareContract("ArgentAccount");
    // TODO Those two can go away once we have support for deploying cairo1 accounts (should only be used in upgrade tests)
    oldArgentAccountClassHash = await declareContract("OldArgentAccount"); 
    proxyClassHash = await declareContract("Proxy"); 
    // const testDappClassHash = await declareContract("TestDapp");
    // testDapp = await deployAndLoadContract(testDappClassHash);
    console.log("\tSetup done...");
  });

  beforeEach(async () => {
    // TODO When everything is more clean, we could deploy a new funded cairo1 account and use that one to do all the logic
  });

  xdescribe("Example tests", function () {
    it("Deploy a contract without guardian", async function () {
      const contract = await deployAndLoadAccountContract(argentAccountClassHash, 12);
      const result = await contract.call("get_guardian");
      expect(result).to.equal(0n);
    });

    it("Deploy a contract with guardian", async function () {
      const contract = await deployAndLoadAccountContract(argentAccountClassHash, 12, 42);
      const result = await contract.call("get_guardian");
      expect(result).to.equal(42n);
    });

    it("Expect an error when owner is zero", async function () {
      await expectRevertWithErrorMessage("argent/null-owner", async () => {
        await account.deployContract({
          classHash: argentAccountClassHash,
          constructorCalldata: CallData.compile({ owner: 0, guardian: 12 }),
        });
      });
    });

    it("Expect event AccountCreated(contract_address, owner, guardian) to be triggered when deploying a contract", async function () {
      const owner = "21";
      const guardian = "42";
      const constructorCalldata = CallData.compile({ owner, guardian });
      const { transaction_hash, contract_address } = await account.deployContract({
        classHash: argentAccountClassHash,
        constructorCalldata,
      });
      const ownerAsHex = num.toHex(owner);
      const guardiangAsHex = num.toHex(guardian);
      await expectEvent(transaction_hash, "AccountCreated", [contract_address, ownerAsHex, guardiangAsHex]);
    });

    it("Should be possible to send eth with a Cairo1 account", async function () {
      const account = await getCairo1Account(proxyClassHash, oldArgentAccountClassHash, argentAccountClassHash);
      const recipient = "0x42";
      const amount = uint256.bnToUint256(1000);
      const ethContract = await getEthContract();
      const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipientInitialBalance } = await ethContract.balanceOf(recipient);
      ethContract.connect(account);
      // TODO it should be possible to do this at some point
      // await ethContract.transfer(recipient, amount);
      const { transaction_hash: transferTxHash } = await account.execute(
        [
          {
            contractAddress: ethContract.address,
            entrypoint: "transfer",
            calldata: CallData.compile({ recipient, amount }),
          },
        ],
        undefined,
        { cairoVersion: "1" },
      );
      await account.waitForTransaction(transferTxHash);
      const { balance: senderFinalBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipientFinalBalance } = await ethContract.balanceOf(recipient);
      // Before amount should be higher than (after + transfer) amount due to fee
      expect(uint256.uint256ToBN(senderInitialBalance) + 1000n > uint256.uint256ToBN(senderFinalBalance)).to.be.true
      expect(uint256.uint256ToBN(recipientInitialBalance) + 1000n).to.equal(uint256.uint256ToBN(recipientFinalBalance));
    });

    it("Should be possible to send eth with a Cairo1 account using a multicall", async function () {
      const account = await getCairo1Account(proxyClassHash, oldArgentAccountClassHash, argentAccountClassHash);
      const recipient1 = "0x42";
      const amount1 = uint256.bnToUint256(1000);
      const recipient2 = "0x43";
      const amount2 = uint256.bnToUint256(42000);
      const ethContract = await getEthContract();

      const { balance: senderInitialBalance } = await ethContract.balanceOf(account.address);
      const { balance: recipient1InitialBalance } = await ethContract.balanceOf(recipient1);
      const { balance: recipient2InitialBalance } = await ethContract.balanceOf(recipient2);

      const { transaction_hash: transferTxHash } = await account.execute(
        [
          {
            contractAddress: ethContract.address,
            entrypoint: "transfer",
            calldata: CallData.compile({ recipient: recipient1, amount: amount1 }),
          },
          {
            contractAddress: ethContract.address,
            entrypoint: "transfer",
            calldata: CallData.compile({ recipient: recipient2, amount: amount2 }),
          },
        ],
        undefined,
        { cairoVersion: "1" },
      );
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
      const account = await getCairo1Account(proxyClassHash, oldArgentAccountClassHash, argentAccountClassHash);

      await expectRevertWithErrorMessage("argent/no-multicall-to-self", async () => {
        const recipient = "0x42";
        const amount = uint256.bnToUint256(1000);
        await account.execute(
          [
            {
              contractAddress: ethAddress,
              entrypoint: "transfer",
              calldata: CallData.compile({ recipient, amount }),
            },
            {
              contractAddress: account.address,
              entrypoint: "trigger_escape_owner",
              calldata: [],
            },
          ],
          undefined,
          { cairoVersion: "1" },
        );
      });
    });

    it("Should be possible to trigger escape guardian by the owner alone", async function () {
      const privateKey = stark.randomAddress();
      const starkKeyPub = ec.starkCurve.getStarkKey(privateKey);
      const account = await deployCairo1AccountWithGuardian(
        proxyClassHash,
        oldArgentAccountClassHash,
        argentAccountClassHash,
        privateKey,
        "0x42",
      );

      const accountContract = await loadContract(account.address);
      const owner = await accountContract.get_owner();
      expect(owner).to.equal(BigInt(starkKeyPub));
      const guardianKeyPub = ec.starkCurve.getStarkKey("0x42");
      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(BigInt(guardianKeyPub));

      await setTime(42);
      await account.execute(
        {
          contractAddress: account.address,
          entrypoint: "trigger_escape_guardian",
          calldata: CallData.compile({ new_guardian: "0x43" }),
        },
        undefined,
        { cairoVersion: "1" },
      );
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(1n);
      expect(escape.active_at).to.equal(42n + 604800n);
    });

    it("Should be possible to escape a guardian by the owner alone", async function () {
      const privateKey = stark.randomAddress();
      const account = await deployCairo1AccountWithGuardian(
        proxyClassHash,
        oldArgentAccountClassHash,
        argentAccountClassHash,
        privateKey,
        "0x42",
      );

      await setTime(42);
      await account.execute(
        {
          contractAddress: account.address,
          entrypoint: "trigger_escape_guardian",
          calldata: CallData.compile({ new_guardian: "0x43" }),
        },
        undefined,
        { cairoVersion: "1" },
      );
      await increaseTime(604800);

      await account.execute(
        {
          contractAddress: account.address,
          entrypoint: "escape_guardian",
          calldata: [],
        },
        undefined,
        { cairoVersion: "1" },
      );

      const accountContract = await loadContract(account.address);
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(0n);
      expect(escape.active_at).to.equal(0n);
      const guardian = await accountContract.get_guardian();
      expect(guardian).to.equal(BigInt("0x43"));
    });

    it("Should use GUARDIAN signature when escaping owner", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployCairo1AccountWithGuardian(
        proxyClassHash,
        oldArgentAccountClassHash,
        argentAccountClassHash,
        ownerPrivateKey,
        guardianPrivateKey,
      );

      account.signer = new Signer(guardianPrivateKey);
      await account.execute(
        {
          contractAddress: account.address,
          entrypoint: "trigger_escape_owner",
          calldata: CallData.compile({ new_owner: "0x42" }),
        },
        undefined,
        { cairoVersion: "1" },
      );

      await setTime(42);
      const accountContract = await loadContract(account.address);
      const escape = await accountContract.get_escape();
      expect(escape.escape_type).to.equal(2n);
      expect(Number(escape.active_at)).to.be.greaterThanOrEqual(Number(42n + 604800n));
    });

    it("Should use signature from BOTH OWNER and GUARDIAN when there is a GUARDIAN", async function () {
      const ownerPrivateKey = stark.randomAddress();
      const guardianPrivateKey = stark.randomAddress();
      const account = await deployCairo1AccountWithGuardian(
        proxyClassHash,
        oldArgentAccountClassHash,
        argentAccountClassHash,
        ownerPrivateKey,
        guardianPrivateKey,
      );

      const accountContract = await loadContract(account.address);
      const guardianBackupBefore = await accountContract.get_guardian_backup();
      expect(guardianBackupBefore).to.equal(0n);
      account.signer = new ArgentSigner(ownerPrivateKey, guardianPrivateKey);
      await account.execute(
        {
          contractAddress: account.address,
          entrypoint: "change_guardian_backup",
          calldata: CallData.compile({ new_guardian_backup: "0x42" }),
        },
        undefined,
        { cairoVersion: "1" },
      );
      const guardianBackupAfter = await accountContract.get_guardian_backup();
      expect(guardianBackupAfter).to.equal(BigInt("0x42"));
    });
  });

  xit("Should be posssible to deploy an argent account version 0.3.0", async function () {
    // await deployAccount(argentAccountClassHash);
    // TODO Impossible atm needs not (yet) available version of Starknet
  });

  xit("Should be possible change owner", async function () {
    // TODO This will involve passing new owner + R + S And test that this iss correct
    // TupleSize4LegacyHash::hash(0, (CHANGE_OWNER_SELECTOR, chain_id, get_contract_address(), _signer::read()));
  });
  xit("Should sign messages from OWNER and GUARDIAN when there is a GUARDIAN (case with BACKUP)", async function () {
    // TODO
  });
});
