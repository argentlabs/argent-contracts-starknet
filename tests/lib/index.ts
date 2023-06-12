import chai from "chai";
import chaiAsPromised from "chai-as-promised";

chai.use(chaiAsPromised);
chai.should();

export const ESCAPE_SECURITY_PERIOD = 7n * 24n * 60n * 60n; // 7 days
export const ESCAPE_EXPIRY_PERIOD = 2n * 7n * 24n * 60n * 60n; // 14 days

export const ESCAPE_TYPE_GUARDIAN = 1n;
export const ESCAPE_TYPE_OWNER = 2n;

export * from "./accounts";
export * from "./contracts";
export * from "./devnet";
export * from "./expectations";
export * from "./outsideExecution";
export * from "./provider";
export * from "./signers";
export * from "./upgrade";
export * from "./multisig";
