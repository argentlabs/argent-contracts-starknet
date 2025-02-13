use starknet::{ContractAddress, account::Call};

// Interface ID for revision 0 of the OutsideExecute interface
// see https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
pub const ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0: felt252 =
    0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181;

// Interface ID for revision 1 of the OutsideExecute interface
// see https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
// calculated using https://github.com/ericnordelo/src5-rs
pub const ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1: felt252 =
    0x1d1144bb2138366ff28d8e9ab57456b1d332ac42196230c3a602003c89872;

/// @notice As defined in SNIP-9 https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
/// @param caller Only the address specified here will be allowed to call `execute_from_outside`
/// As an exception, to opt-out of this check, the value 'ANY_CALLER' can be used
/// @param nonce It can be any value as long as it's unique. Prevents signature reuse
/// @param execute_after `execute_from_outside` only succeeds if executing after this time
/// @param execute_before `execute_from_outside` only succeeds if executing before this time
/// @param calls The calls that will be executed by the Account
/// Using `Call` here instead of re-declaring `OutsideCall` to avoid the conversion
#[derive(Copy, Drop, Serde)]
pub struct OutsideExecution {
    pub caller: ContractAddress,
    pub nonce: felt252,
    pub execute_after: u64,
    pub execute_before: u64,
    pub calls: Span<Call>,
}

/// @notice get_outside_execution_message_hash_rev_* is not part of the standard interface
#[starknet::interface]
pub trait IOutsideExecution<TContractState> {
    /// @notice This function allows anyone to submit a transaction on behalf of the account as long as they have the
    /// relevant signatures
    /// @param outside_execution The parameters of the transaction to execute
    /// @param signature A valid signature on the SNIP-12 message encoding of `outside_execution`
    /// @notice This function does not allow reentrancy. A call to `__execute__` or `execute_from_outside` cannot
    /// trigger another nested transaction to `execute_from_outside`.
    fn execute_from_outside(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Array<felt252>,
    ) -> Array<Span<felt252>>;

    /// @notice Outside execution using SNIP-12 Rev 1
    fn execute_from_outside_v2(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Span<felt252>,
    ) -> Array<Span<felt252>>;

    /// Get the status for a given nonce
    /// @return true if the nonce is available to use
    fn is_valid_outside_execution_nonce(self: @TContractState, nonce: felt252) -> bool;

    /// Get the message hash for some `OutsideExecution` rev 0 following SNIP-12. Can be used to know what needs to be
    /// signed
    fn get_outside_execution_message_hash_rev_0(self: @TContractState, outside_execution: OutsideExecution) -> felt252;

    /// Get the message hash for some `OutsideExecution` rev 1 following SNIP-12. Can be used to know what needs to be
    /// signed
    fn get_outside_execution_message_hash_rev_1(self: @TContractState, outside_execution: OutsideExecution) -> felt252;
}

/// This trait must be implemented when using the component `outside_execution_component` (This is enforced by the
/// compiler)
pub trait IOutsideExecutionCallback<TContractState> {
    /// @notice Callback performed after checking the OutsideExecution is valid
    /// @dev Make the correct access control checks in this callback
    /// @param calls The calls to be performed
    /// @param outside_execution_hash The hash of OutsideExecution
    /// @param raw_signature The signature that the user gave for this transaction
    #[inline(always)]
    fn execute_from_outside_callback(
        ref self: TContractState, calls: Span<Call>, outside_execution_hash: felt252, raw_signature: Span<felt252>,
    ) -> Array<Span<felt252>>;
}


/// @dev If you are using this component you have to support it in the `supports_interface` function
// This is achieved by adding outside_execution::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
#[starknet::component]
pub mod outside_execution_component {
    use argent::outside_execution::{
        outside_execution::{IOutsideExecution, IOutsideExecutionCallback, OutsideExecution},
        outside_execution_hash::{OffChainMessageOutsideExecutionRev0, OffChainMessageOutsideExecutionRev1},
    };
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};
    use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{get_block_timestamp, get_caller_address, storage::Map};

    #[storage]
    pub struct Storage {
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: Map<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(OutsideExecutionImpl)]
    impl ImplOutsideExecution<
        TContractState,
        +HasComponent<TContractState>,
        +IOutsideExecutionCallback<TContractState>,
        +Drop<TContractState>,
        +ReentrancyGuardComponent::HasComponent<TContractState>,
    > of IOutsideExecution<ComponentState<TContractState>> {
        fn execute_from_outside(
            ref self: ComponentState<TContractState>, outside_execution: OutsideExecution, signature: Array<felt252>,
        ) -> Array<Span<felt252>> {
            let hash = outside_execution.get_message_hash_rev_0();
            self.assert_valid_outside_execution(outside_execution, hash, signature.span())
        }

        fn execute_from_outside_v2(
            ref self: ComponentState<TContractState>, outside_execution: OutsideExecution, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            let hash = outside_execution.get_message_hash_rev_1();
            self.assert_valid_outside_execution(outside_execution, hash, signature)
        }

        fn get_outside_execution_message_hash_rev_0(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution,
        ) -> felt252 {
            outside_execution.get_message_hash_rev_0()
        }

        fn get_outside_execution_message_hash_rev_1(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution,
        ) -> felt252 {
            outside_execution.get_message_hash_rev_1()
        }

        fn is_valid_outside_execution_nonce(self: @ComponentState<TContractState>, nonce: felt252) -> bool {
            !self.outside_nonces.read(nonce)
        }
    }

    #[generate_trait]
    impl Internal<
        TContractState,
        +HasComponent<TContractState>,
        +IOutsideExecutionCallback<TContractState>,
        +Drop<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn assert_valid_outside_execution(
            ref self: ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            outside_tx_hash: felt252,
            signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            let mut reentrancy_guard = get_dep_component_mut!(ref self, ReentrancyGuard);
            reentrancy_guard.start();

            if outside_execution.caller.into() != 'ANY_CALLER' {
                assert(get_caller_address() == outside_execution.caller, 'argent/invalid-caller');
            }

            let block_timestamp = get_block_timestamp();
            assert(
                outside_execution.execute_after < block_timestamp && block_timestamp < outside_execution.execute_before,
                'argent/invalid-timestamp',
            );
            let nonce = outside_execution.nonce;
            assert(!self.outside_nonces.read(nonce), 'argent/duplicated-outside-nonce');
            self.outside_nonces.write(nonce, true);
            let mut state = self.get_contract_mut();
            let result = state.execute_from_outside_callback(outside_execution.calls, outside_tx_hash, signature);
            reentrancy_guard.end();
            result
        }
    }
}

