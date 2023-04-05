import { Account, ec, CallData, constants, Provider, hash } from "starknet";

const provider = new Provider({ sequencer: { network: constants.NetworkName.SN_GOERLI } });

const classHash = "0x5615a467315e50346075d7a53c784f118a741e6997e0a22beb3aee9a9c1d302";


// const privateKey = ec.starkCurve.randomAddress();
const privateKey = "0x04884667fe9a260c005e8e51cd46da344720617aeae547a4f294d131fe56bd27";
console.log(`privateKey=${privateKey}`);
const starkKeyPair = ec.starkCurve.getStarkKey(privateKey);
const starkKeyPub = ec.starkCurve.getStarkKey(starkKeyPair);
console.log(`publicKey=${starkKeyPub}`);

// Precompute address
const constructorCalldata = CallData.compile({ owner: starkKeyPub, guardian: "0"});
const argentAccount = hash.calculateContractAddressFromHash(
    starkKeyPub,
    classHash,
    constructorCalldata,
    0
);
console.log(`Precalculated account address=${argentAccount}`);


// Actually deploy account
const account = new Account(provider, argentAccount, starkKeyPair);

// will fait the 1st time, you'll need to fund the account so he's able to pay for his own deploy
// Unless you use my PK 
const { transaction_hash, contract_address } = await account.deployAccount({
    classHash,
    constructorCalldata,
    addressSalt: starkKeyPub
});

await provider.waitForTransaction(transaction_hash);
console.log('✅ New argent account created.\n   address =', contract_address);
