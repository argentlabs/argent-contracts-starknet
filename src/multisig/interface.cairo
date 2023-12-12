use argent::common::version::Version;

/// Deprecated methods for compatibility reasons
#[starknet::interface]
trait IDeprecatedArgentMultisig<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    /// For compatibility reasons this method returns 1 when the signature is valid, and panics otherwise
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}
