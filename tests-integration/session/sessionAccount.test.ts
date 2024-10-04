import { Contract, num } from "starknet";
import {
  AllowedMethod,
  StarknetKeyPair,
  compileSessionSignature,
  deployAccount,
  deployer,
  executeWithCustomSig,
  expectRevertWithErrorMessage,
  manager,
  randomStarknetKeyPair,
  setupSession,
} from "../../lib";

describe("Hybrid Session Account: execute calls", function () {
  let sessionAccountClassHash: string;
  let mockDappContract: Contract;
  const initialTime = 1710167933n;

  before(async () => {
    sessionAccountClassHash = await manager.declareLocalContract("ArgentAccount");

    const mockDappClassHash = await manager.declareLocalContract("MockDapp");
    const deployedMockDapp = await deployer.deployContract({
      classHash: mockDappClassHash,
      salt: num.toHex(randomStarknetKeyPair().privateKey),
    });
    mockDappContract = await manager.loadContract(deployedMockDapp.contract_address);
  });

  beforeEach(async function () {
    await manager.setTime(initialTime);
  });

  for (const useTxV3 of [false, true]) {
    it(`Execute basic session (TxV3: ${useTxV3})`, async function () {
      const { accountContract, account, guardian } = await deployAccount({
        useTxV3,
        classHash: sessionAccountClassHash,
      });

      const allowedMethods: AllowedMethod[] = [
        {
          "Contract Address": mockDappContract.address,
          selector: "set_number_double",
        },
      ];

      const { accountWithDappSigner } = await setupSession(
        guardian as StarknetKeyPair,
        account,
        allowedMethods,
        initialTime + 150n,
      );

      const calls = [mockDappContract.populateTransaction.set_number_double(2)];

      const { transaction_hash } = await accountWithDappSigner.execute(calls);

      await account.waitForTransaction(transaction_hash);
      await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);
    });
  }

  it("Only execute tx if session not expired", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const expiresAt = initialTime + 60n * 24n;

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { accountWithDappSigner } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );
    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    // non expired session
    await manager.setTime(expiresAt - 10800n);
    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Expired session
    await manager.setTime(expiresAt + 7200n);
    await expectRevertWithErrorMessage(
      "session/expired",
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);
  });

  it("Revoke a session", async function () {
    const { accountContract, account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
    ];

    const { accountWithDappSigner, sessionHash } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const calls = [mockDappContract.populateTransaction.set_number_double(2)];

    const { transaction_hash } = await accountWithDappSigner.execute(calls);

    await account.waitForTransaction(transaction_hash);
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

    // Revoke Session
    await accountContract.revoke_session(sessionHash);
    await accountContract.is_session_revoked(sessionHash).should.eventually.be.true;
    await expectRevertWithErrorMessage(
      "session/revoked",
      accountWithDappSigner.execute(calls, undefined, { maxFee: 1e16 }),
    );
    await mockDappContract.get_number(accountContract.address).should.eventually.equal(4n);

    await expectRevertWithErrorMessage("session/already-revoked", accountContract.revoke_session(sessionHash));
  });

  it("Fail if proofs are misaligned", async function () {
    const { account, guardian } = await deployAccount({ classHash: sessionAccountClassHash });

    const allowedMethods: AllowedMethod[] = [
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_double",
      },
      {
        "Contract Address": mockDappContract.address,
        selector: "set_number_times3",
      },
      {
        "Contract Address": mockDappContract.address,
        selector: "increase_number",
      },
    ];

    const calls = [
      mockDappContract.populateTransaction.set_number_double(2),
      mockDappContract.populateTransaction.set_number_double(4),
      mockDappContract.populateTransaction.increase_number(2),
      mockDappContract.populateTransaction.increase_number(2),
    ];

    const { accountWithDappSigner, dappService, sessionRequest, authorizationSignature } = await setupSession(
      guardian as StarknetKeyPair,
      account,
      allowedMethods,
      initialTime + 150n,
    );

    const sessionToken = await dappService.getSessionToken({
      calls,
      account: accountWithDappSigner,
      completedSession: sessionRequest,
      sessionAuthorizationSignature: authorizationSignature,
      isLegacyAccount: false,
      cacheAuthorization: false,
    });
    const sessionTokenWrongProofs = {
      ...sessionToken,
      proofs: [["0x2", "0x1"]],
    };

    // happens when the the number of proofs is not equal to the number of calls
    await expectRevertWithErrorMessage(
      "session/unaligned-proofs",
      executeWithCustomSig(accountWithDappSigner, calls, compileSessionSignature(sessionTokenWrongProofs)),
    );
  });
});
