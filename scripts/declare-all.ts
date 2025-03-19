import { manager } from "../lib";

await manager.declareLocalContract("ArgentAccount");
await manager.declareLocalContract("MockDapp");
await manager.declareFixtureContract("Proxy");
await manager.declareFixtureContract("Account-0.2.3.1");
await manager.declareLocalContract("AccountUpgradeable");
await manager.declareLocalContract("ArgentMultisigAccount");
await manager.declareLocalContract("StableAddressDeployer");
await manager.declareLocalContract("MockFutureArgentAccount");
