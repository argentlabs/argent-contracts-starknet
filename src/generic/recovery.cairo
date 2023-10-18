#[derive(Drop, Copy, Serde, PartialEq)]
enum EscapeStatus {
    /// No escape triggered, or it was canceled
    None,
    /// Escape was triggered and it's waiting for the `escapeSecurityPeriod`
    NotReady,
    /// The security period has elapsed and the escape is ready to be completed
    Ready,
    /// No confirmation happened for `escapeExpiryPeriod` since it became `Ready`. The escape cannot be completed now, only canceled
    Expired,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
struct Escape {
    // timestamp for activation of escape mode, 0 otherwise
    ready_at: u64,
    // target signer address
    target_signer: felt252,
    // new signer address
    new_signer: felt252,
}

#[derive(Drop, Copy, Serde, starknet::StorePacking)]
struct EscapeEnabled {
    // The escape is enabled
    is_enabled: bool,
    // Time it takes for the escape to become ready after being triggered
    security_period: u64,
    //  The escape will be ready and can be completed for this duration
    expiry_period: u64,
}