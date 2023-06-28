import { declareContract, deployAccountWithoutGuardian } from "./lib";
import { deployMultisig } from "./lib/multisig";

const ERC165_IERC165_INTERFACE_ID = BigInt("0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055");
const ERC165_IERC165_INTERFACE_ID_OLD = BigInt("0x01ffc9a7");
const ERC165_ACCOUNT_INTERFACE_ID = BigInt("0x32a450d0828523e159d5faa1f8bc3c94c05c819aeb09ec5527cd8795b5b5067");
const ERC165_ACCOUNT_INTERFACE_ID_OLD_1 = BigInt("0xa66bd575");
const ERC165_ACCOUNT_INTERFACE_ID_OLD_2 = BigInt("0x3943f10f");
const ERC165_OUTSIDE_EXECUTION_INTERFACE = BigInt("0x3a8eb057036a72671e68e4bad061bbf5740d19351298b5e2960d72d76d34cb9");

describe("ERC169", function () {
  it("ArgentAccount", async function () {
    const { accountContract } = await deployAccountWithoutGuardian(await declareContract("ArgentAccount"));
    await accountContract.supports_interface(0).should.eventually.be.false;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID_OLD).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_1).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_2).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE).should.eventually.be.true;
  });

  it("ArgentMultisig", async function () {
    const { accountContract } = await deployMultisig(await declareContract("ArgentMultisig"), 1, 1);
    await accountContract.supports_interface(0).should.eventually.be.false;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID_OLD).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_1).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_2).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE).should.eventually.be.true;
  });
});
