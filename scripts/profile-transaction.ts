import { makeProfiler } from "../tests-integration/lib/gas";

const transactions = {
  "Transaction label 1": "0x111111111111111111111111111111111111111111111111111111111111111",
  "Transaction label 2": "0x222222222222222222222222222222222222222222222222222222222222222",
};

const profiler = makeProfiler();

for (const [name, transaction_hash] of Object.entries(transactions)) {
  await profiler.profile(name, { transaction_hash });
}

profiler.printReport();
