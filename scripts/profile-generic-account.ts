import { Signature as EthersSignature, Signature, Wallet, id } from "ethers";
import { Account, CairoCustomEnum, CallData, hash, num, uint256 } from "starknet";
import {
  KeyPair,
  MultisigSigner,
  declareContract,
  deployer,
  fundAccount,
  loadContract,
  provider,
  randomKeyPair,
} from "../tests-integration/lib";
import { makeProfiler } from "../tests-integration/lib/gas";

const genericAccountClassHash = await declareContract("ArgentGenericAccount");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);
const profiler = makeProfiler();

// To be able to run this script using the devnet, update the start-devnet.sh script to ignore this line:
// export STARKNET_DEVNET_CAIRO_VM=rust

function ethereumSignatureType(signer: bigint, signature: Signature) {
  return CallData.compile([
    new CairoCustomEnum({
      Starknet: undefined,
      Secp256k1: {
        signer,
        r: uint256.bnToUint256(signature.r),
        s: uint256.bnToUint256(signature.s),
        y_parity: signature.yParity.toString(),
      },
      Webauthn: undefined,
      Secp256r1: undefined,
    }),
  ]);
}

class EthKeyPair extends KeyPair {
  public get publicKey() {
    return BigInt(new Wallet(id(this.privateKey.toString())).address);
  }

  public signHash(messageHash: string) {
    const eth_signer = new Wallet(id(this.privateKey.toString()));
    if (messageHash.length < 66) {
      messageHash = "0x" + "0".repeat(66 - messageHash.length) + messageHash.slice(2);
    }
    const signature = EthersSignature.from(eth_signer.signingKey.sign(messageHash));

    return ethereumSignatureType(this.publicKey, signature);
  }
}

{
  const name = "[GA] 1 Starknet signature";
  console.log(name);
  const owners = [new KeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 1 Ethereum signature";
  console.log(name);
  const owners = [new EthKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Starknet signature";
  console.log(name);
  const owners = [new KeyPair(), new KeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Ethereum signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 3 Starknet signature";
  console.log(name);
  const owners = [new KeyPair(), new KeyPair(), new KeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 3 Ethereum signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair(), new EthKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 1 Eth + 1 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair(), new KeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Eth + 1 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair(), new KeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 1 Eth + 20 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair()];
  for (let i = 0; i < 20; i++) {
    owners.push(new KeyPair());
  }
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

async function deployGenericAccount(owners: KeyPair[]) {
  const salt = num.toHex(randomKeyPair().privateKey);
  const constructorCalldata = CallData.compile({
    new_threshold: owners.length,
    signers: owners.map((o) => num.toHex(o.publicKey)),
  });

  const contractAddress = hash.calculateContractAddressFromHash(salt, genericAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15, "ETH"); // 0.001 ETH

  const sorted_owners = owners.sort((key1, key2) => Number(key1.publicKey - key2.publicKey));
  const account = new Account(provider, contractAddress, new MultisigSigner(sorted_owners), "1");

  const { transaction_hash } = await account.deploySelf({
    classHash: genericAccountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  return account;
}

profiler.printReport();
