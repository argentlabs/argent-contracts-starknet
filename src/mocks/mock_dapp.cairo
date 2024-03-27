use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IMockDapp<TContractState> {
    fn set_number(ref self: TContractState, number: felt252);
    fn set_number_double(ref self: TContractState, number: felt252);
    fn set_number_times3(ref self: TContractState, number: felt252);
    fn increase_number(ref self: TContractState, number: felt252) -> felt252;
    fn throw_error(ref self: TContractState, number: felt252);

    fn get_number(self: @TContractState, user: ContractAddress) -> felt252;
    fn library_call(
        self: @TContractState, class_hash: ClassHash, selector: felt252, calldata: Span<felt252>
    ) -> Span<felt252>;
    fn doit(self: @TContractState, class_hash: ClassHash, message: Array<u8>) -> Span<felt252>;
}

#[starknet::contract]
mod MockDapp {
    use alexandria_math::sha256::sha256;
    use argent::utils::bytes::{U256IntoSpanU8, SpanU8TryIntoU256, SpanU8TryIntoFelt252, extend, u32s_to_u256};
    use argent::utils::hashing::{sha256_cairo0};
    use starknet::{ContractAddress, ClassHash, get_caller_address, library_call_syscall};

    #[storage]
    struct Storage {
        stored_number: LegacyMap<ContractAddress, felt252>,
    }

    #[abi(embed_v0)]
    impl MockDappImpl of super::IMockDapp<ContractState> {
        fn set_number(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number);
        }

        fn set_number_double(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number * 2);
        }

        fn set_number_times3(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number * 3);
        }

        fn increase_number(ref self: ContractState, number: felt252) -> felt252 {
            let user = get_caller_address();
            let val = self.stored_number.read(user);
            let new_number = val + number;
            self.stored_number.write(user, new_number);
            new_number
        }

        fn throw_error(ref self: ContractState, number: felt252) {
            assert(0 == 1, 'test dapp reverted')
        }

        fn get_number(self: @ContractState, user: ContractAddress) -> felt252 {
            self.stored_number.read(user)
        }

        fn library_call(
            self: @ContractState, class_hash: ClassHash, selector: felt252, calldata: Span<felt252>
        ) -> Span<felt252> {
            library_call_syscall(class_hash, selector, calldata).expect('library call failed')
        }

        fn doit(self: @ContractState, class_hash: ClassHash, message: Array<u8>) -> Span<felt252> {
            let hash_cairo1 = sha256(message.clone()).span();
            let hash_cairo1_u256: u256 = hash_cairo1.try_into().expect('invalid-message');
            println!("hash cairo1 len: {}", hash_cairo1.len());

            let hash_cairo0 = sha256_cairo0(message.span());
            println!("hash cairo0 len: {}", hash_cairo0.len());
            let hash_cairo0_u256 = u32s_to_u256(hash_cairo0);
            println!("hash: {}", hash_cairo0_u256);
            assert!(hash_cairo0_u256 == hash_cairo1_u256, "mismatch");
            let expected = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763;
            assert!(hash_cairo0_u256 == expected, "foo");

            let hash_cairo0_u8: Span<u8> = hash_cairo0_u256.into();
            assert!(hash_cairo1 == hash_cairo0_u8, "mismatch u8");
            hash_cairo0
        }
    }
}
