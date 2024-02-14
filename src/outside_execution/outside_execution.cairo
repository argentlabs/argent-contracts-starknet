/// @dev If you are using this component you have to support it in the `supports_interface` function
// This is achieved by adding outside_execution::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
#[starknet::component]
mod outside_execution_component {
    use argent::outside_execution::interface::{IOutsideExecution, OutsideExecution, IOutsideExecutionCallback};
    use hash::{HashStateTrait, HashStateExTrait};
    use pedersen::PedersenTrait;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp, get_tx_info, account::Call};

    const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
        selector!(
            "OutsideExecution(caller:felt,nonce:felt,execute_after:felt,execute_before:felt,calls_len:felt,calls:OutsideCall*)OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"
        );

    #[derive(Copy, Drop, Hash)]
    struct StarkNetDomain {
        name: felt252,
        version: felt252,
        chain_id: felt252,
    }

    #[storage]
    struct Storage {
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: LegacyMap<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(OutsideExecutionImpl)]
    impl OutsideExecuction<
        TContractState, +HasComponent<TContractState>, +IOutsideExecutionCallback<TContractState>, +Drop<TContractState>
    > of IOutsideExecution<ComponentState<TContractState>> {
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
            self.outside_nonces.write(nonce, true);

            let outside_tx_hash = self.hash_outside_execution_message(@outside_execution);
            let mut state = self.get_contract_mut();
            state.execute_from_outside_callback(outside_execution.calls, outside_tx_hash, signature.span())
        }

        fn get_outside_execution_message_hash(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution
        ) -> felt252 {
            self.hash_outside_execution_message(@outside_execution)
        }

        fn is_valid_outside_execution_nonce(self: @ComponentState<TContractState>, nonce: felt252) -> bool {
            !self.outside_nonces.read(nonce)
        }
    }

    #[generate_trait]
    impl Private<TContractState, +HasComponent<TContractState>> of PrivateTrait<TContractState> {
        #[inline(always)]
        fn hash_domain(self: @ComponentState<TContractState>, domain: @StarkNetDomain) -> felt252 {
            PedersenTrait::new(0)
                .update_with(selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)"))
                .update_with(*domain)
                .update_with(4)
                .finalize()
        }

        fn hash_outside_call(self: @ComponentState<TContractState>, outside_call: @Call) -> felt252 {
            let mut state = PedersenTrait::new(0);
            let mut calldata_span = outside_call.calldata.span();
            let calldata_len = outside_call.calldata.len().into();
            let calldata_hash = loop {
                match calldata_span.pop_front() {
                    Option::Some(item) => state = state.update(*item),
                    Option::None => { break state.update(calldata_len).finalize(); },
                }
            };

            PedersenTrait::new(0)
                .update(selector!("OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"))
                .update((*outside_call.to).into())
                .update(*outside_call.selector)
                .update(calldata_len)
                .update(calldata_hash)
                .update(5)
                .finalize()
        }

        fn hash_outside_execution(
            self: @ComponentState<TContractState>, outside_execution: @OutsideExecution
        ) -> felt252 {
            let mut state = PedersenTrait::new(0);
            let mut calls_span = *outside_execution.calls;
            let calls_len = (*outside_execution.calls).len().into();
            let calls_hash = loop {
                match calls_span.pop_front() {
                    Option::Some(call) => state = state.update(self.hash_outside_call(call)),
                    Option::None => { break state.update(calls_len).finalize(); },
                }
            };

            PedersenTrait::new(0)
                .update(OUTSIDE_EXECUTION_TYPE_HASH)
                .update((*outside_execution.caller).into())
                .update(*outside_execution.nonce)
                .update((*outside_execution.execute_after).into())
                .update((*outside_execution.execute_before).into())
                .update(calls_len)
                .update(calls_hash)
                .update(7)
                .finalize()
        }

        #[inline(always)]
        fn hash_outside_execution_message(
            self: @ComponentState<TContractState>, outside_execution: @OutsideExecution
        ) -> felt252 {
            let domain = StarkNetDomain {
                name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id,
            };

            PedersenTrait::new(0)
                .update('StarkNet Message')
                .update(self.hash_domain(@domain))
                .update(get_contract_address().into())
                .update(self.hash_outside_execution(outside_execution))
                .update(4)
                .finalize()
        }
    }
}

