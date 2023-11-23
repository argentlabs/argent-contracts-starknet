import { Account, ArraySignatureType, CallData, hash, num } from "starknet";
import {
  EthKeyPair,
  RawSigner,
  StarknetKeyPair,
  declareContract,
  deployer,
  fundAccount,
  loadContract,
  provider,
  randomKeyPair,
} from "../tests-integration/lib";
import { reportProfile } from "../tests-integration/lib/gas";

const genericAccountClassHash = await declareContract("ArgentGenericAccount");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);

const table: Record<string, any> = {};

class GenericSigner extends RawSigner {
  constructor(public keys: StarknetKeyPair[]) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const compiledData = this.keys
      .sort((key1, key2) => Number(key1.publicKey - key2.publicKey))
      .map((key) => {
        return key.signHash(messageHash);
      });
    return CallData.compile([compiledData]);
  }
}

{
  const name = "[GA] 1 Starknet signature";
  console.log(name);
  const owners = [new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 1 Ethereum signature";
  console.log(name);
  const owners = [new EthKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Starknet signature";
  console.log(name);
  const owners = [new StarknetKeyPair(), new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Ethereum signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 3 Starknet signature";
  console.log(name);
  const owners = [new StarknetKeyPair(), new StarknetKeyPair(), new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 3 Ethereum signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair(), new EthKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 1 Eth + 1 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair(), new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Eth + 1 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair(), new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 1 Eth + 20 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair()];
  for (let i = 0; i < 20; i++) {
    owners.push(new StarknetKeyPair());
  }
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await reportProfile(table, name, await testDappContract.set_number(42));
}

async function deployGenericAccount(owners: StarknetKeyPair[]) {
  const salt = num.toHex(randomKeyPair().privateKey);
  const constructorCalldata = CallData.compile({
    new_threshold: owners.length,
    signers: owners.map((o) => num.toHex(o.publicKey)),
  });

  const contractAddress = hash.calculateContractAddressFromHash(salt, genericAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15); // 0.001 ETH

  const account = new Account(provider, contractAddress, new GenericSigner(owners), "1");

  const { transaction_hash } = await account.deploySelf({
    classHash: genericAccountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  return account;
}

console.table(table);
