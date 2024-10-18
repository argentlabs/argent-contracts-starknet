/// @dev If you are using this component you have to support it in the `supports_interface` function
// This is achieved by adding outside_execution::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
#[starknet::component]
mod outside_execution_component {
    use argent::outside_execution::{
        outside_execution_hash::{OffChainMessageOutsideExecutionRev2},
        interface::{OutsideExecution, IOutsideExecutionCallback, IOutsideExecution}
    };
    use hash::{HashStateTrait, HashStateExTrait};
    use openzeppelin::security::reentrancyguard::{
        ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl
    };
    use pedersen::PedersenTrait;
    use starknet::{
        get_caller_address, get_contract_address, get_block_timestamp, get_tx_info, account::Call,
        storage::Map
    };
    use core::starknet::storage_access::StorePacking;
    use core::integer::bitwise;

    #[storage]
    struct Storage {
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: Map<felt252, u128>,
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
        fn execute_from_outside_v3(
            ref self: ComponentState<TContractState>,
            outside_execution: OutsideExecution,
            signature: Span<felt252>
        ) -> Array<Span<felt252>> {
            let hash = outside_execution.get_message_hash_rev_1();
            self.assert_valid_outside_execution(outside_execution, hash, signature)
        }

        fn get_outside_execution_message_hash_rev_2(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution
        ) -> felt252 {
            outside_execution.get_message_hash_rev_1()
        }

        fn is_valid_outside_execution_v3_nonce(
            self: @ComponentState<TContractState>, nonce: (felt252, u128)
        ) -> bool {
            let (channel, mask) = nonce;
            if mask == 0_u128 {
                return false;
            }

            let current_mask = self.outside_nonces.read(channel);
            (current_mask & mask) == 0
        }

        fn get_outside_execution_v3_channel_nonce(
            self: @ComponentState<TContractState>, channel: felt252
        ) -> u128 {
            self.outside_nonces.read(channel)
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
                outside_execution.execute_after < block_timestamp
                    && block_timestamp < outside_execution.execute_before,
                'argent/invalid-timestamp'
            );
            let (channel, mask) = outside_execution.nonce;
            let current_mask = self.outside_nonces.read(channel);
            let (and, _, or) = bitwise(current_mask, mask);
            assert(mask != 0 && and == 0, 'argent/invalid-outside-nonce');
            self.outside_nonces.write(channel, or);
            let mut state = self.get_contract_mut();
            let result = state
                .execute_from_outside_callback(outside_execution.calls, outside_tx_hash, signature);
            reentrancy_guard.end();
            result
        }
    }
}
