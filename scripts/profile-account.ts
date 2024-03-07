import {
  deployAccount,
  deployAccountWithoutGuardian,
  deployOldAccount,
  deployContract,
  provider,
  signChangeOwnerMessage,
  starknetSignatureType,
  LegacyKeyPair,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const mockDappContract = await deployContract("MockDapp");

const profiler = newProfiler(provider);

{
  const { account } = await deployAccount();
  mockDappContract.connect(account);
  await profiler.profile("Set number", await mockDappContract.set_number(42));
}

{
  const { account } = await deployAccountWithoutGuardian();
  mockDappContract.connect(account);
  await profiler.profile("Set number without guardian", await mockDappContract.set_number(42));
}

{
  const { account } = await deployOldAccount();
  mockDappContract.connect(account);
  await profiler.profile("Set number using old account", await mockDappContract.set_number(42));
}

{
  const { account, accountContract } = await deployAccount();
  const owner = await accountContract.get_owner();
  const newOwner = new LegacyKeyPair();
  const chainId = await provider.getChainId();
  const [r, s] = await signChangeOwnerMessage(account.address, owner, newOwner, chainId);
  await profiler.profile(
    "Change owner",
    await accountContract.change_owner(starknetSignatureType(newOwner.publicKey, r, s)),
  );
}

profiler.printSummary();
profiler.updateOrCheckReport();
