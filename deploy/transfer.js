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






// Check balance - should be 100
console.log(`Calling Starknet for account balance...`);
const balanceInitial = await erc20.balanceOf(account0.address);
console.log("account0 has a balance of :", uint256.uint256ToBN(balanceInitial.balance).toString());

// Mint 1000 tokens to account address
const amountToMint = uint256.bnToUint256(1000);
console.log("Invoke Tx - Minting 1000 tokens to account0...");
const { transaction_hash: mintTxHash } = await erc20.mint(
    account0.address,
    amountToMint,
    { maxFee: 900_000_000_000_000 }
);

// Wait for the invoke transaction to be accepted on Starknet
console.log(`Waiting for Tx to be Accepted on Starknet - Minting...`);
await provider.waitForTransaction(mintTxHash);

// Check balance - should be 1100
console.log(`Calling Starknet for account balance...`);
const balanceBeforeTransfer = await erc20.balanceOf(account0.address);
console.log("account0 has a balance of :", uint256.uint256ToBN(balanceBeforeTransfer.balance).toString());

// Execute tx transfer of 10 tokens
console.log(`Invoke Tx - Transfer 10 tokens back to erc20 contract...`);
const toTransferTk: uint256.Uint256 = uint256.bnToUint256(10);
const transferCallData = stark.compileCalldata({
    recipient: erc20Address,
    initial_supply: { type: 'struct', low: toTransferTk.low, high: toTransferTk.high }
});

const { transaction_hash: transferTxHash } = await account0.execute({
    contractAddress: erc20Address,
    entrypoint: "transfer",
    calldata: transferCallData, },
    undefined,
    { maxFee: 900_000_000_000_000 }
);

// Wait for the invoke transaction to be accepted on Starknet
console.log(`Waiting for Tx to be Accepted on Starknet - Transfer...`);
await provider.waitForTransaction(transferTxHash);

// Check balance after transfer - should be 1090
console.log(`Calling Starknet for account balance...`);
const balanceAfterTransfer = await erc20.balanceOf(account0.address);
console.log("account0 has a balance of :", uint256.uint256ToBN(balanceAfterTransfer.balance).toString());
console.log("✅ Script completed.");