/// @dev If you are using this component you have to support it in the `supports_interface` function
// This is achieved by adding outside_execution::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
#[starknet::component]
mod outside_execution_component {
    use argent::outside_execution::{
        outside_execution_hash::{OffChainMessageOutsideExecutionRev0, OffChainMessageOutsideExecutionRev1},
        interface::{OutsideExecution, IOutsideExecutionCallback, IOutsideExecution}
    };
    use hash::{HashStateTrait, HashStateExTrait};
    use openzeppelin::security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};
    use pedersen::PedersenTrait;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp, get_tx_info, account::Call};

    #[storage]
    struct Storage {
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: LegacyMap<felt252, bool>,
    }
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(OutsideExecutionImpl)]
    impl ImplOutsideExecution<
        TContractState,
        +HasComponent<TContractState>,
        +IOutsideExecutionCallback<TContractState>,
        +Drop<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
    > of IOutsideExecution<ComponentState<TContractState>> {
        fn execute_from_outside(
            ref self: ComponentState<TContractState>, outside_execution: OutsideExecution, signature: Array<felt252>
        ) -> Array<Span<felt252>> {
            let hash = outside_execution.get_message_hash_rev_0();
            self.assert_valid_outside_execution(outside_execution, hash, signature.span())
        }

        fn execute_from_outside_v2(
            ref self: ComponentState<TContractState>, outside_execution: OutsideExecution, signature: Span<felt252>
        ) -> Array<Span<felt252>> {
            let hash = outside_execution.get_message_hash_rev_1();
            self.assert_valid_outside_execution(outside_execution, hash, signature)
        }

        fn get_outside_execution_message_hash_rev_0(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution
        ) -> felt252 {
            outside_execution.get_message_hash_rev_0()
        }

        fn get_outside_execution_message_hash_rev_1(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution
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
            signature: Span<felt252>
        ) -> Array<Span<felt252>> {
            let mut reentrancy_guard = get_dep_component_mut!(ref self, ReentrancyGuard);
            reentrancy_guard.start();

            if outside_execution.caller.into() != 'ANY_CALLER' {
                assert(get_caller_address() == outside_execution.caller, 'argent/invalid-caller');
            }

            let block_timestamp = get_block_timestamp();
            assert(
                outside_execution.execute_after < block_timestamp && block_timestamp < outside_execution.execute_before,
                'argent/invalid-timestamp'
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

