import { declareContract, deployAccountWithoutGuardian } from "./lib";
import { deployMultisig } from "./lib/multisig";

const ERC165_IERC165_INTERFACE_ID = BigInt("0x01ffc9a7");
const ERC165_ACCOUNT_INTERFACE_ID = BigInt("0x396002e72b10861a183bd73bd37e3a27a36b685f488f45c2d3e664d0009e51c");
const ERC165_ACCOUNT_INTERFACE_ID_OLD_1 = BigInt("0xa66bd575");
const ERC165_ACCOUNT_INTERFACE_ID_OLD_2 = BigInt("0x3943f10f");

describe("Erc169", function () {
  it("ArgentAccount", async function () {
    const { accountContract } = await deployAccountWithoutGuardian(await declareContract("ArgentAccount"));
    await accountContract.supports_interface(0).should.eventually.equal(false);
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID).should.eventually.equal(true);
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID).should.eventually.equal(true);
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_1).should.eventually.equal(true);
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_2).should.eventually.equal(true);
  });

  it("Multisig", async function () {
    const { accountContract } = await deployMultisig(await declareContract("ArgentMultisig"), 1, 1);
    await accountContract.supports_interface(0).should.eventually.equal(false);
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID).should.eventually.equal(true);
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID).should.eventually.equal(true);
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_1).should.eventually.equal(true);
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_2).should.eventually.equal(true);
  });
});
