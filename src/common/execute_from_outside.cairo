#[starknet::component]
mod execute_from_outside_component {
    use argent::common::{
        calls::execute_multicall,
        outside_execution::{
            IOutsideExecutionTrait, OutsideExecution, hash_outside_execution_message, IOutsideExecutionCallback
        }
    };
    use starknet::{get_caller_address, get_block_timestamp};

    #[storage]
    struct Storage {
        // TODO DO A TEST IF UPGRADE TO THIS, STORAGE STAYS THE SAME
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: LegacyMap<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        TransactionExecuted: TransactionExecuted,
    }

    #[derive(Drop, starknet::Event)]
    struct TransactionExecuted {
        #[key]
        hash: felt252,
        response: Span<Span<felt252>>
    }

    #[embeddable_as(OutsideExecutionImpl)]
    impl OutsideExecuctionTrait<
        TContractState, +HasComponent<TContractState>, +IOutsideExecutionCallback<TContractState>, +Drop<TContractState>
    > of IOutsideExecutionTrait<ComponentState<TContractState>> {
        fn execute_from_outside(
            ref self: ComponentState<TContractState>, outside_execution: OutsideExecution, signature: Array<felt252>
        ) -> Array<Span<felt252>> {
            // Checks
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

            let outside_tx_hash = hash_outside_execution_message(@outside_execution);

            let mut state = self.get_contract_mut();
            state.assert_valid_calls_and_signature_callback(outside_execution.calls, outside_tx_hash, signature.span());

            // Effects
            self.outside_nonces.write(nonce, true);

            // Interactions
            let retdata = execute_multicall(outside_execution.calls);

            self.emit(TransactionExecuted { hash: outside_tx_hash, response: retdata.span() });
            retdata
        }

        fn get_outside_execution_message_hash(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution
        ) -> felt252 {
            hash_outside_execution_message(@outside_execution)
        }

        fn is_valid_outside_execution_nonce(self: @ComponentState<TContractState>, nonce: felt252) -> bool {
            !self.outside_nonces.read(nonce)
        }
    }

    #[generate_trait]
    impl PrivateListImpl<TContractState> of PrivateListTrait<TContractState> {}
}
