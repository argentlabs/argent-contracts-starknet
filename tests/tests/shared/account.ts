import { Account, CairoVersion, CallData, Signer, ec, hash, stark } from "starknet";
import { account, provider } from "./constants";
import { fundAccount } from "./devnetInteraction";

async function deployOldAccount(
  proxyClassHash: string,
  oldArgentAccountClassHash: string,
  privateKey?: string | Signer,
  publicKey?: string,
) {
  // stark.randomAddress() for testing purposes only, this is not safe in production
  privateKey = privateKey || stark.randomAddress();
  publicKey = publicKey || ec.starkCurve.getStarkKey(privateKey as string); // Need to force string type (maybe there is a better way?)

  const constructorCalldata = CallData.compile({
    implementation: oldArgentAccountClassHash,
    selector: hash.getSelectorFromName("initialize"),
    calldata: CallData.compile({ signer: publicKey, guardian: "0" }),
  });

  const contractAddress = hash.calculateContractAddressFromHash(publicKey, proxyClassHash, constructorCalldata, 0);

  const accountToDeploy = new Account(provider, contractAddress, privateKey);
  await fundAccount(accountToDeploy.address);

  const { transaction_hash } = await accountToDeploy.deployAccount({
    classHash: proxyClassHash,
    constructorCalldata,
    contractAddress,
    addressSalt: publicKey,
  });
  await account.waitForTransaction(transaction_hash);
  return accountToDeploy;
}

// TODO Can't do YET
// TODO Could be handy to store the hash and rename to getAccount()
async function deployAccount(argentAccountClassHash: string) {
  const privateKey = stark.randomAddress();
  const publicKey = ec.starkCurve.getStarkKey(privateKey);

  const constructorCalldata = CallData.compile({ signer: publicKey, guardian: "0" });
  const contractAddress = hash.calculateContractAddressFromHash(
    publicKey,
    argentAccountClassHash,
    constructorCalldata,
    0,
  );

  const accountToDeploy = new Account(provider, contractAddress, privateKey);
  await fundAccount(accountToDeploy.address);

  const { transaction_hash } = await account.deployAccount({
    classHash: argentAccountClassHash,
    constructorCalldata,
    addressSalt: publicKey,
  });
  await account.waitForTransaction(transaction_hash);
  return accountToDeploy;
}
async function upgradeAccount(
  accountToUpgrade: Account,
  argentAccountClassHash: string,
  cairoVersion: CairoVersion = "0",
) {
  const { transaction_hash: transferTxHash } = await accountToUpgrade.execute(
    {
      contractAddress: accountToUpgrade.address,
      entrypoint: "upgrade",
      calldata: CallData.compile({ implementation: argentAccountClassHash, calldata: ["0"] }),
    },
    undefined,
    { cairoVersion },
  );
  await provider.waitForTransaction(transferTxHash);
}

// TODO tmp method (we can't deploy cairo1 account yet)
async function getCairo1Account(
  proxyClassHash: string,
  oldArgentAccountClassHash: string,
  argentAccountClassHash: string,
) {
  const accountToUpgrade = await deployOldAccount(proxyClassHash, oldArgentAccountClassHash);
  await upgradeAccount(accountToUpgrade, argentAccountClassHash);
  return accountToUpgrade;
}

export { deployAccount, deployOldAccount, upgradeAccount, getCairo1Account };
