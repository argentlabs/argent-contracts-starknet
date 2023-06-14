mod argent_account;
use argent_account::{
    IArgentAccount, IArgentAccountDispatcher, IArgentAccountDispatcherTrait, ArgentAccount
};

mod escape;
use escape::{Escape, EscapeStatus};

#[cfg(test)]
mod tests;
