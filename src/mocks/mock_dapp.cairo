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
    fn doit(self: @TContractState, class_hash: ClassHash);
}

#[starknet::contract]
mod MockDapp {
    use alexandria_math::sha256::sha256;
    use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252, extend};
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

        fn doit(self: @ContractState, class_hash: ClassHash) {
            let expected = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763;

            let message = array!['l', 'o', 'c', 'a', 'l', 'h', 'o', 's', 't'];
            let message_hash: u256 = sha256(message).span().try_into().expect('invalid-message');
            println!("hash1: {}", message_hash);
            assert!(message_hash == expected, "invalid-message-hash");

            let message = array!['loca', 'lhos', 't\x00\x00\x00'];
            let mut calldata = array![];
            message.serialize(ref calldata);
            calldata.append(9);
            let res = library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()).unwrap();
            assert!(res.len() == 9, "invalid-res-length");
            let message_hash = u32s_to_u256(res.slice(1, 8));
            println!("hash2: {}", message_hash);
            assert!(message_hash == expected, "invalid-message-hash2");
        }
    }

    fn u32s_to_u256(arr: Span<felt252>) -> u256 {
        assert(arr.len() == 8, 'INVALID_FELT252s_U256_CONV_LEN');
        let high = *arr.at(0) * 0x1000000000000000000000000
            + *arr.at(1) * 0x10000000000000000
            + *arr.at(2) * 0x100000000
            + *arr.at(3);
        let low = *arr.at(4) * 0x1000000000000000000000000
            + *arr.at(5) * 0x10000000000000000
            + *arr.at(6) * 0x100000000
            + *arr.at(7);
        u256 { high: high.try_into().unwrap(), low: low.try_into().unwrap() }
    }
}
