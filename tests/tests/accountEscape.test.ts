import { expect } from "chai";
import { Signer, stark } from "starknet";
import { declareContract, deployAccount, increaseTime, loadContract, setTime } from "./shared";

describe("ArgentAccount: escape mechanism", function () {
  // Avoid timeout
  this.timeout(320000);

  let argentAccountClassHash: string;

  before(async () => {
    argentAccountClassHash = await declareContract("ArgentAccount");
  });

  it("Should be possible to trigger_escape_guardian by the OWNER alone", async function () {
    const ownerPrivateKey = stark.randomAddress();
    const guardianPrivateKey = stark.randomAddress();
    const account = await deployAccount(argentAccountClassHash, ownerPrivateKey, guardianPrivateKey);
    const accountContract = await loadContract(account.address);

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
});
