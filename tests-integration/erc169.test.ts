import { deployAccountWithoutGuardian } from "./lib";
import { deployMultisig1_1 } from "./lib/multisig";

const ERC165_IERC165_INTERFACE_ID = BigInt("0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055");
const ERC165_IERC165_INTERFACE_ID_OLD = BigInt("0x01ffc9a7");
const ERC165_ACCOUNT_INTERFACE_ID = BigInt("0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd");
const ERC165_ACCOUNT_INTERFACE_ID_OLD_1 = BigInt("0xa66bd575");
const ERC165_ACCOUNT_INTERFACE_ID_OLD_2 = BigInt("0x3943f10f");
const ERC165_OUTSIDE_EXECUTION_INTERFACE = BigInt("0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181");

describe("ERC169", function () {
  it("ArgentAccount", async function () {
    const { accountContract } = await deployAccountWithoutGuardian();
    await accountContract.supports_interface(0).should.eventually.be.false;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID_OLD).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_1).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_2).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE).should.eventually.be.true;
  });

  it("ArgentMultisig", async function () {
    const { accountContract } = await deployMultisig1_1();
    await accountContract.supports_interface(0).should.eventually.be.false;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_IERC165_INTERFACE_ID_OLD).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_1).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_ACCOUNT_INTERFACE_ID_OLD_2).should.eventually.be.true;
    await accountContract.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE).should.eventually.be.true;
  });
});
