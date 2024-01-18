import { Signature as EthersSignature, Signature, Wallet, id } from "ethers";
import { Account, ArraySignatureType, CairoCustomEnum, CallData, hash, num, uint256 } from "starknet";
import {
  KeyPair,
  RawSigner,
  declareContract,
  deployer,
  fundAccount,
  loadContract,
  provider,
  randomKeyPair,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const genericAccountClassHash = await declareContract("ArgentGenericAccount");
const testDappClassHash = await declareContract("TestDapp");
const { contract_address } = await deployer.deployContract({ classHash: testDappClassHash });
const testDappContract = await loadContract(contract_address);
const profiler = newProfiler(provider);

// To be able to run this script using the devnet, update the start-devnet.sh script to ignore this line:
// export STARKNET_DEVNET_CAIRO_VM=rust
class GenericSigner extends RawSigner {
  constructor(public keys: StarknetKeyPair[]) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const response = [this.keys.length.toString()];
    this.keys
      .sort((key1, key2) => Number(key1.publicKey - key2.publicKey))
      .map((key) => {
        response.push(...key.signHash(messageHash));
      });
    return response;
  }
}

function starknetSignatureType(r: string, s: string) {
  return new CairoCustomEnum({
    Starknet: { r, s },
    Secp256k1: undefined,
    Webauthn: undefined,
    Secp256r1: undefined,
  });
}

function ethereumSignatureType(signature: Signature) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: {
      r: uint256.bnToUint256(signature.r),
      s: uint256.bnToUint256(signature.s),
      y_parity: signature.yParity.toString(),
    },
    Webauthn: undefined,
    Secp256r1: undefined,
  });
}

class StarknetKeyPair extends KeyPair {
  public signHash(messageHash: string) {
    const [r, s] = super.signHash(messageHash);
    return CallData.compile({
      signer: super.publicKey,
      signer_type: starknetSignatureType(r, s),
    });
  }
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

    return CallData.compile({
      signer: this.publicKey,
      signer_type: ethereumSignatureType(signature),
    });
  }
}

{
  const name = "[GA] 1 Starknet signature";
  console.log(name);
  const owners = [new StarknetKeyPair()];
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
  const owners = [new StarknetKeyPair(), new StarknetKeyPair()];
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
  const owners = [new StarknetKeyPair(), new StarknetKeyPair(), new StarknetKeyPair()];
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
  const owners = [new EthKeyPair(), new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
}

{
  const name = "[GA] 2 Eth + 1 Starknet signature";
  console.log(name);
  const owners = [new EthKeyPair(), new EthKeyPair(), new StarknetKeyPair()];
  const account = await deployGenericAccount(owners);
  testDappContract.connect(account);
  await profiler.profile(name, await testDappContract.set_number(42));
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
  await profiler.profile(name, await testDappContract.set_number(42));
}

async function deployGenericAccount(owners: StarknetKeyPair[]) {
  const salt = num.toHex(randomKeyPair().privateKey);
  const constructorCalldata = CallData.compile({
    new_threshold: owners.length,
    signers: owners.map((o) => num.toHex(o.publicKey)),
  });

  const contractAddress = hash.calculateContractAddressFromHash(salt, genericAccountClassHash, constructorCalldata, 0);
  await fundAccount(contractAddress, 1e15, "ETH"); // 0.001 ETH

  const account = new Account(provider, contractAddress, new GenericSigner(owners), "1");

  const { transaction_hash } = await account.deploySelf({
    classHash: genericAccountClassHash,
    constructorCalldata,
    addressSalt: salt,
  });
  await provider.waitForTransaction(transaction_hash);
  return account;
}

profiler.printProfiles();
