import chai from "chai";
import chaiAsPromised from "chai-as-promised";

chai.use(chaiAsPromised);
chai.should();

export * from "./accounts";
export * from "./contracts";
export * from "./devnet";
export * from "./events";
export * from "./expectations";
export * from "./manager";
export * from "./multisig";
export * from "./openZeppelinAccount";
export * from "./outsideExecution";
export * from "./receipts";
export * from "./recovery";
export * from "./session/argentServices";
export * from "./session/session";
export * from "./session/sessionServices";
export * from "./signers/legacy";
export * from "./signers/secp256";
export * from "./signers/signers";
export * from "./signers/webauthn";
export * from "./tokens";
export * from "./udc";
export * from "./upgrade";

export type Constructor<T> = new (...args: any[]) => T;
