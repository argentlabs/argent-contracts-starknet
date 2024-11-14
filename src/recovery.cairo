/// @notice The status of the Escape
#[derive(Drop, Copy, Serde, PartialEq, Debug)]
enum EscapeStatus {
    /// No escape triggered, or it was canceled
    None,
    /// Escape was triggered and it's waiting for the `security_period`
    NotReady,
    /// The security period has elapsed and the escape is ready to be completed
    Ready,
    /// No confirmation happened for `expiry_period` since it became `Ready`. The escape cannot be completed now, only
    /// canceled
    Expired,
}
