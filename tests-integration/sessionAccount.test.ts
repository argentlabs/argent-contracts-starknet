import { num, Contract, selector, uint256 } from "starknet";
import {
  declareContract,
  deploySessionAccount,
  loadContract,
  randomKeyPair,
  deployer,
  AllowedMethod,
  DappService,
  TokenLimit,
  BackendService,
  DappSigner,
  ArgentX,
  setTime,
  expectRevertWithErrorMessage,
} from "./lib";
import { expect } from "chai";

const tokenLimits: TokenLimit[] = [{ contract_address: "0x100", amount: uint256.bnToUint256(10) }];

const dappService = new DappService();

describe("Hybrid Session Account: execute calls", function () {
  let sessionAccountClassHash: string;
  let testDappOneContract: Contract;

  before(async () => {
    sessionAccountClassHash = await declareContract("HybridSessionAccount");

    const testDappClassHash = await declareContract("TestDapp");
    const deployedTestDappOne = await deployer.deployContract({
      classHash: testDappClassHash,
      salt: num.toHex(randomKeyPair().privateKey),
    });
    testDappOneContract = await loadContract(deployedTestDappOne.contract_address);
  });

  it("Call a contract with backend signer", async function () {
    const { accountContract, account, guardian } = await deploySessionAccount(sessionAccountClassHash);

    const backendService = new BackendService(guardian);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        contract_address: testDappOneContract.address,
        selector: selector.getSelectorFromName("set_number_double"),
      },
    ];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, tokenLimits);

    // 2. Wallet signs session
    const ownerSignature = await argentX.getOwnerSessionSignature(sessionRequest);

    // Every request:
    const calls = [testDappOneContract.populateTransaction.set_number_double(2)];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const sessionSigner = new DappSigner(argentX, dappService.keypair, ownerSignature, sessionRequest);

    account.signer = sessionSigner;

    const { transaction_hash } = await account.execute(calls);
    await account.waitForTransaction(transaction_hash);
    await testDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Revert if session is expired", async function () {
    const { account, guardian } = await deploySessionAccount(sessionAccountClassHash);

    const backendService = new BackendService(guardian);
    const argentX = new ArgentX(account, backendService);

    const allowedMethods: AllowedMethod[] = [
      {
        contract_address: testDappOneContract.address,
        selector: selector.getSelectorFromName("set_number_double"),
      },
      {
        contract_address: testDappOneContract.address,
        selector: selector.getSelectorFromName("set_number_times3"),
      },
    ];

    const expiry = 200;

    const sessionRequest = dappService.createSessionRequest(allowedMethods, tokenLimits, expiry);

    const ownerSignature = await argentX.getOwnerSessionSignature(sessionRequest);

    // Every request:
    const calls = [testDappOneContract.populateTransaction.set_number_double(2)];

    const sessionSigner = new DappSigner(argentX, dappService.keypair, ownerSignature, sessionRequest);

    account.signer = sessionSigner;

    await account.execute(calls);
    await setTime(expiry + 10);
    expectRevertWithErrorMessage("session-revoked", async () => {
      const { transaction_hash } = await account.execute(calls);
      return await account.waitForTransaction(transaction_hash);
    });
  });
});
