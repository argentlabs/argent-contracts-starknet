import {
  deployAccount,
  deployAccountWithoutGuardian,
  deployOldAccount,
  deployContract,
  provider,
  KeyPair,
  signChangeOwnerMessage,
} from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const testDappContract = await deployContract("TestDapp");

const profiler = newProfiler(provider);

{
  const { account } = await deployAccount();
  testDappContract.connect(account);
  await profiler.profile("Set number", await testDappContract.set_number(42));
}

{
  const { account } = await deployAccountWithoutGuardian();
  testDappContract.connect(account);
  await profiler.profile("Set number without guardian", await testDappContract.set_number(42));
}

{
  const { account } = await deployOldAccount();
  testDappContract.connect(account);
  await profiler.profile("Set number using old account", await testDappContract.set_number(42));
}

{
  const { account, accountContract } = await deployAccount();
  const owner = await accountContract.get_owner();
  const newOwner = new KeyPair();
  const chainId = await provider.getChainId();
  const [r, s] = await signChangeOwnerMessage(account.address, owner, newOwner, chainId);
  await profiler.profile("Change owner", await accountContract.change_owner(newOwner.publicKey, r, s));
}

profiler.printSummary();
profiler.updateOrCheckReport();
