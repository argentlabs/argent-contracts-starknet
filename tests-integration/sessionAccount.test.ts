import { num, Contract, selector, uint256 } from "starknet";
import {
  declareContract,
  deploySessionAccount,
  loadContract,
  randomKeyPair,
  deployer,
  getOwnerSessionSignature,
  AllowedMethod,
  DappService,
  TokenLimit,
  BackendService,
  DappSigner,
  ArgentX,
} from "./lib";
import { expect } from "chai";

const tokenLimits: TokenLimit[] = [{ contract_address: "0x100", amount: uint256.bnToUint256(10) }];

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
    const { accountContract, account } = await deploySessionAccount(sessionAccountClassHash);

    const backendService = new BackendService();
    const dappService = new DappService();
    const argentX = new ArgentX(accountContract.address, backendService);

    // Session creation:
    // 1. dapp request session: provides dapp pub key and policies
    const allowedMethods: AllowedMethod[] = [
      {
        contract_address: testDappOneContract.address,
        selector: selector.getSelectorFromName("set_number_double"),
      },
    ];

    const sessionRequest = dappService.createSessionRequestForBackend(allowedMethods, tokenLimits);

    // 2. wallet ask backend: provide dapps key, policies. In return it gets backend key
    const backendPublicKey = argentX.sendSessionInitiationToBackend(sessionRequest);

    // backend key gets added to session
    const sessionTokenToSign = dappService.createSessionToSign(sessionRequest, backendPublicKey);

    //3. Wallet signs session and sends it to the dapp
    const ownerSignature = await getOwnerSessionSignature(sessionTokenToSign, account);

    // Every request:
    const calls = [testDappOneContract.populateTransaction.set_number_double(2)];

    // 1. dapp requests backend signature
    // backend: can verify the parameters and check it was signed by the account then provides signature
    // 2. dapp signs tx and session, crafts signature and submits transaction
    const sessionSigner = new DappSigner(backendService, dappService.keypair, ownerSignature, sessionTokenToSign);

    account.signer = sessionSigner;

    const { transaction_hash } = await account.execute(calls);
    await account.waitForTransaction(transaction_hash);
    await testDappOneContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  // 1. Dapps sends session to wallet 
  // 2. user signs session, sends to backend, backend signs
  //
  // 1. dapp creates dapp signer, sends session to account
  //
  //
  //
  //
  //
});
