import { Contract, uint256 } from "starknet";
import { deployAccount, getEthContract } from "../lib";

describe.only("ArgentAccount: testing all signers", function () {
  const accounts: any[] = [];
  let ethContract: Contract;
  const recipient = "0xadbe1";
  const amount = uint256.bnToUint256(1);

  before(async () => {
    ethContract = await getEthContract();
    const { account } = await deployAccount();
    accounts.push({ name: "regular account", account });
    console.log(accounts);
  });

  for (const { name, account } of accounts) {
    it.only(`Testing ${name}`, async function () {
      // ethContract.connect(account);
      // await ethContract.transfer(recipient, amount);
    });
  }
});
