import { CairoOption, CairoOptionVariant, CallData, Contract } from "starknet";
import {
  AllowedMethod,
  EstimateStarknetKeyPair,
  SignerType,
  StarknetKeyPair,
  deployAccount,
  estimateWithCustomSig,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
  generateRandomNumber,
  manager,
  randomStarknetKeyPair,
  setupSession,
  signerTypeToCustomEnum,
} from "../../lib";
import { singleMethodAllowList } from "./sessionTestHelpers";

describe("ArgentAccount: session basics", function () {
  let sessionAccountClassHash: string;
  let mockDappContract: Contract;
  let randomNumber: bigint;
  const initialTime = 1710167933n;

  before(async () => {
    sessionAccountClassHash = await manager.declareLocalContract("ArgentAccount");
    mockDappContract = await manager.declareAndDeployContract("MockDapp");
  });

  beforeEach(async function () {
    await manager.setTime(initialTime);
    randomNumber = generateRandomNumber();
  });

  it(`Execute basic session`, async function () {
    const { accountContract, account, guardian } = await deployAccount({
      classHash: sessionAccountClassHash,
    });

    const { accountWithDappSigner } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber);
  });

  it(`Should be possible to estimate a basic session given an invalid guardian signature`, async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const estimateGuardian = new EstimateStarknetKeyPair((guardian as StarknetKeyPair).publicKey);
    const { accountWithDappSigner, sessionRequest, authorizationSignature, dappService } = await setupSession({
      guardian: estimateGuardian,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];
    const sessionToken = await dappService.getSessionToken({
      calls,
      account: accountWithDappSigner,
      completedSession: sessionRequest,
      authorizationSignature,
    });

    // Should pass when estimating
    await estimateWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature());
    // Should fail when executing
    await expectRevertWithErrorMessage(
      "session/invalid-backend-sig",
      executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature(), { skipValidate: true }),
    );
  });

  it(`Should be possible to estimate a basic session given an invalid session signature`, async function () {
    const { account, guardian } = await deployAccount();

    const { accountWithDappSigner, sessionRequest, authorizationSignature, dappService } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];
    const sessionToken = await dappService.getSessionToken({
      calls,
      account: accountWithDappSigner,
      completedSession: sessionRequest,
      authorizationSignature,
    });

    const pubkey = sessionToken.sessionSignature.variant.Starknet.pubkey;
    sessionToken.sessionSignature = signerTypeToCustomEnum(SignerType.Starknet, {
      pubkey,
      r: 42,
      s: 69,
    });

    // Should pass when estimating
    await estimateWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature());

    // Should fail when executing
    await expectRevertWithErrorMessage(
      "session/invalid-session-sig",
      executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
    );
  });

  it(`Execute basic session when there a multiple owners`, async function () {
    const { accountContract, account, guardian } = await deployAccount({
      classHash: sessionAccountClassHash,
    });

    const newOwner1 = randomStarknetKeyPair();
    const newOwner2 = randomStarknetKeyPair();
    await accountContract.change_owners(
      CallData.compile({
        remove: [],
        add: [newOwner1.signer, newOwner2.signer],
        alive_signature: new CairoOption(CairoOptionVariant.None),
      }),
    );
    const { accountWithDappSigner } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber);
  });

  it("Only execute tx if session not expired", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const expiresAt = initialTime + 60n * 24n;

    const { accountWithDappSigner } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    // non expired session
    await manager.setTime(expiresAt - 10800n);
    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber);

    // Expired session
    await manager.setTime(expiresAt + 7200n);
    await expectRevertWithErrorMessage("session/expired", accountWithDappSigner.execute(calls));
  });

  it("Revoke a session", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const { accountWithDappSigner, sessionHash } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods: singleMethodAllowList(mockDappContract, "set_number"),
    });

    const calls = [mockDappContract.populateTransaction.set_number(randomNumber)];

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber);
    // Revoke Session
    await accountContract.revoke_session(sessionHash);
    await accountContract.is_session_revoked(sessionHash).should.eventually.be.true;
    await expectRevertWithErrorMessage("session/revoked", accountWithDappSigner.execute(calls));
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(randomNumber);

    await expectRevertWithErrorMessage("session/already-revoked", accountContract.revoke_session(sessionHash));
  });

  it("Fail if proofs are misaligned", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number",
      },
      {
        "Contract Address": mockDappContract.address,
        selector: "increase_number",
      },
    ];

    const calls = [
      mockDappContract.populateTransaction.set_number(2),
      mockDappContract.populateTransaction.set_number(4),
      mockDappContract.populateTransaction.increase_number(2),
    ];

    const { sessionRequest, authorizationSignature, dappService, accountWithDappSigner } = await setupSession({
      guardian: guardian as StarknetKeyPair,
      account,
      expiry: initialTime + 150n,
      allowedMethods,
    });

    const sessionToken = await dappService.getSessionToken({
      calls,
      account: accountWithDappSigner,
      completedSession: sessionRequest,
      authorizationSignature,
    });
    sessionToken.proofs = [["0x1", "0x2"]];

    // happens when the the number of proofs is not equal to the number of calls
    await expectRevertWithErrorMessage(
      "session/unaligned-proofs",
      executeWithCustomSig(accountWithDappSigner, calls, sessionToken.compileSignature()),
    );
  });
});
