import { uint256 } from "starknet";
import { StarknetKeyPair, WebauthnOwner, deployAccount, manager, upgradeAccount } from "../lib";
import { newProfiler } from "../lib/gas";

const profiler = newProfiler(manager);
const fundingAmount = 2e16;

let privateKey: string;
if (manager.isDevnet) {
  // With the KeyPairs hardcoded, we gotta reset to avoid some issues
  await manager.restart();
  privateKey = "0x1";
  manager.clearClassCache();
} else {
  privateKey = new StarknetKeyPair().privateKey;
}

const ethContract = await manager.tokens.ethContract();
const recipient = "0xadbe1";
const amount = uint256.bnToUint256(1);
const starknetOwner = new StarknetKeyPair(privateKey);
const guardian = new StarknetKeyPair(42n);
const profilerClassHash = await manager.declareLocalContract("ArgentAccountProfile");
const latestClassHash = await manager.declareLocalContract("ArgentAccount");
{
  const { account } = await deployAccount({
    classHash: profilerClassHash,
    owner: new WebauthnOwner(privateKey),
    guardian,
    salt: "0x8",
    fundingAmount,
  });

  await upgradeAccount(account, latestClassHash);

  ethContract.connect(account);
  await profiler.profile("Transfer - Webauthn no guardian", await ethContract.transfer(recipient, amount));
}

profiler.printSummary();
profiler.updateOrCheckReport();
