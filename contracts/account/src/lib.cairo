mod argent_account;
use argent_account::IArgentAccount;
use argent_account::IArgentAccountDispatcher;
use argent_account::IArgentAccountDispatcherTrait;
use argent_account::ArgentAccount;

mod escape;
use escape::Escape;
use escape::EscapeStatus;

#[cfg(test)]
mod tests;
