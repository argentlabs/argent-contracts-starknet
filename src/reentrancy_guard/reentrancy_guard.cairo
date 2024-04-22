/// This component helps prevent reentrancy calls to a contract.
/// The functions where reentrancy is not allowed should call `enter_lock` at the beginning of the function and `exit_lock` at the end.
/// `enter_lock_from_non_reentrant` is an optized version of `enter_lock` when it's known with certainty that the function is not called from a reentrant call.
#[starknet::interface]
trait IReentrancyGuard<TContractState> {
    fn enter_lock(ref self: TContractState);
    fn enter_lock_from_non_reentrant(ref self: TContractState);
    fn exit_lock(ref self: TContractState);
}


#[starknet::component]
mod reentrancy_guard_component {
    #[storage]
    struct Storage {
        /// 0 if not in reentrancy, should always be 0 at the end of the transaction
        reentrancy_lock: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(ReentrancyGuardInternalImpl)]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of super::IReentrancyGuard<ComponentState<TContractState>> {
        #[inline(always)]
        fn enter_lock(ref self: ComponentState<TContractState>) {
            assert(self.reentrancy_lock.read() == 0, 'argent/reentrancy');
            self.reentrancy_lock.write(1);
        }

        #[inline(always)]
        fn enter_lock_from_non_reentrant(ref self: ComponentState<TContractState>) {
            self.reentrancy_lock.write(1);
        }

        #[inline(always)]
        fn exit_lock(ref self: ComponentState<TContractState>) {
            self.reentrancy_lock.write(0);
        }
    }
}

