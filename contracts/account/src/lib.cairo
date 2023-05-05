mod argent_account;
use argent_account::ArgentAccount;

mod escape;
use escape::Escape;
use escape::StorageAccessEscape;
use escape::EscapeSerde;
use escape::EscapeStatus;

#[cfg(test)]
mod tests;
