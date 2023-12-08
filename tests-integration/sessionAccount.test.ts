import { num, Contract, selector, uint256 } from "starknet";
import {
  declareContract,
  loadContract,
  randomKeyPair,
  deployer,
  AllowedMethod,
  DappService,
  TokenAmount,
  BackendService,
  DappSigner,
  ArgentX,
  deployAccount,
} from "./lib";

const tokenLimits: TokenAmount[] = [{ token_address: "0x100", amount: uint256.bnToUint256(10) }];

const dappService = new DappService();

describe("Hybrid Session Account: execute calls", function () {
  let sessionAccountClassHash: string;
  let testDappOneContract: Contract;
  let mockErc20Contract: Contract;

  before(async () => {
    sessionAccountClassHash = await declareContract("HybridSessionAccount");

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
    const { accountContract, account, guardian, owner } = await deployAccount(sessionAccountClassHash);

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

    //  Every request:
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

  it("Call a token contract", async function () {
    const { accountContract, account, guardian } = await deployAccount(sessionAccountClassHash);

    const backendService = new BackendService(guardian);
    const argentX = new ArgentX(account, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        contract_address: mockErc20Contract.address,
        selector: selector.getSelectorFromName("mint"),
      },
      {
        contract_address: mockErc20Contract.address,
        selector: selector.getSelectorFromName("approve"),
      },
      {
        contract_address: mockErc20Contract.address,
        selector: selector.getSelectorFromName("transfer_from"),
      },
    ];

    const tokenLimits: TokenAmount[] = [{ token_address: mockErc20Contract.address, amount: uint256.bnToUint256(10) }];

    const sessionRequest = dappService.createSessionRequest(allowedMethods, tokenLimits);

    // 2. Wallet signs session
    const ownerSignature = await argentX.getOwnerSessionSignature(sessionRequest);

    //  Every request:
    const calls = [
      mockErc20Contract.populateTransaction.mint(accountContract.address, 10),
      mockErc20Contract.populateTransaction.approve(accountContract.address, 10),
      mockErc20Contract.populateTransaction.transfer_from(accountContract.address, "0x999", 10),
    ];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const sessionSigner = new DappSigner(argentX, dappService.keypair, ownerSignature, sessionRequest);

    account.signer = sessionSigner;
    const { transaction_hash } = await account.execute(calls);
    await account.waitForTransaction(transaction_hash);
    await mockErc20Contract.balance_of(accountContract.address).should.eventually.equal(0n);
    await mockErc20Contract.balance_of("0x999").should.eventually.equal(10n);
  });
});
