mod interface;
use interface::IArgentAccount;
use interface::IDeprecatedArgentAccount;

mod argent_account;
use argent_account::ArgentAccount;

mod escape;
use escape::{Escape, EscapeStatus};

#[cfg(test)]
mod tests;
