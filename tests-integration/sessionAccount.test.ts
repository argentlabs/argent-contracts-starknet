import { num, Contract } from "starknet";
import {
  declareContract,
  loadContract,
  randomKeyPair,
  deployer,
  AllowedMethod,
  DappService,
  BackendService,
  ArgentX,
  deployAccount,
  getSessionTypedData,
  setTime,
} from "./lib";

describe("Hybrid Session Account: execute calls", function () {
  let sessionAccountClassHash: string;
  let testDappOneContract: Contract;
  let mockErc20Contract: Contract;

  before(async () => {
    sessionAccountClassHash = await declareContract("SessionAccount");

    const testDappClassHash = await declareContract("TestDapp");
    const deployedTestDappOne = await deployer.deployContract({
      classHash: testDappClassHash,
      salt: num.toHex(randomKeyPair().privateKey),
    });
    const erc20ClassHash = await declareContract("Erc20Mock");
    const delpoyedErc20 = await deployer.deployContract({
      classHash: erc20ClassHash,
      salt: num.toHex(randomKeyPair().privateKey),
    });
    mockErc20Contract = await loadContract(delpoyedErc20.contract_address);
    testDappOneContract = await loadContract(deployedTestDappOne.contract_address);
  });

  it("Call a contract with backend signer", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": testDappOneContract.address,
        selector: "set_number_double",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(account.address, allowedMethods);

    // 2. Owner and Guardian signs session
    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    //  Every request:
    const calls = [testDappOneContract.populateTransaction.set_number_double(2)];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await testDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Only execute tx if session not expired", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": testDappOneContract.address,
        selector: "set_number_double",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(account.address, allowedMethods);

    // 2. Owner and Guardian signs session
    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    //  Every request:
    const calls = [testDappOneContract.populateTransaction.set_number_double(2)];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await testDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Expired session
    setTime;
    const { transaction_hash: expired_tx } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(expired_tx);
    await testDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Call a token contract", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const backendService = new BackendService(guardian);
    const dappService = new DappService(backendService);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockErc20Contract.address,
        selector: "mint",
      },
      {
        "Contract Address": mockErc20Contract.address,
        selector: "approve",
      },
      {
        "Contract Address": mockErc20Contract.address,
        selector: "transfer_from",
      },
    ];

    const sessionRequest = dappService.createSessionRequest(account.address, allowedMethods);

    // 2. Wallet signs session
    const accountSessionSignature = await argentX.getOffchainSignature(await getSessionTypedData(sessionRequest));

    //  Every request:
    const calls = [
      mockErc20Contract.populateTransaction.mint(accountContract.address, 10),
      mockErc20Contract.populateTransaction.approve(accountContract.address, 10),
      mockErc20Contract.populateTransaction.transfer_from(accountContract.address, "0x999", 10),
    ];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const accountWithDappSigner = dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      accountSessionSignature,
    );

    const { transaction_hash } = await accountWithDappSigner.execute(calls);
    await account.waitForTransaction(transaction_hash);
    await mockErc20Contract.balance_of(accountContract.address).should.eventually.equal(0n);
    await mockErc20Contract.balance_of("0x999").should.eventually.equal(10n);
  });
});
