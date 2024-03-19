import { provider } from "../tests-integration/lib";
import { newProfiler } from "../tests-integration/lib/gas";

const transactions = {
  "Transaction label 1": "0x048662c5d879d6bdf2e0fcffd08ec2eb7362f399604a3d3e20638933bd4bb2f1",
};

const profiler = newProfiler(provider);

for (const [name, transaction_hash] of Object.entries(transactions)) {
  await profiler.profile(name, { transaction_hash }, { allowFailedTransactions: true });
}

profiler.printSummary();
