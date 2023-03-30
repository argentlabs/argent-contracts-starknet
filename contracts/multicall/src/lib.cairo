mod dummy_syscalls;

mod multicall;
use multicall::Multicall;
use multicall::Multicall::aggregate;

mod test_dapp;
use test_dapp::TestDapp;

#[cfg(test)]
mod tests;
