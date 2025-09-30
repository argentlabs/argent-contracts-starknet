import { ArgentAccount, ArgentSigner, manager, StarknetKeyPair } from "../lib";

const mockDapp = await manager.loadContract("0x20e4fb45e1ada8b9ea95e96dd2fa87056fe852bb6408769f0e19c8f9c39531c");

// Account upgraded from 0.2.3.1 to 0.5.0
const account = new ArgentAccount({
  provider: manager,
  address: "0x00a3e2af0f82c6e8701001611e4efe04cc4ba204252dfa9e700f4915807ec877",
  signer: new ArgentSigner(new StarknetKeyPair("0x00e1e49b9a6ce983dd3a682a4eb4085575731bba9fe77528e01a8d86e10183ff")),
});

mockDapp.providerOrAccount = account;
const estimate = await account.estimateInvokeFee([]);//mockDapp.populateTransaction.set_number(12));
console.log(estimate);
// const x = await account.execute([]);//mockDapp.populateTransaction.set_number(12));
// console.log(x);
