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
}

#[starknet::contract]
mod MockDapp {
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
            // match library_call_syscall(class_hash, selector, calldata) {
            // let client_data: Array<u32> = array!['hell', 'o wo', 'rld\x00'];
            let client_data: Array<u32> = array!['h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', 0];
            // let calldata: Array<u32> = array![];
            let mut calldata: Array<felt252> = array![];
            client_data.serialize(ref calldata);
            // let client_data_u32s_padding: u32 = 1;
            // calldata.append((client_data.len() * 4 - client_data_u32s_padding).into());
            // auth_data_cdata_concat.serialize(ref calldata);
            let calldata = array![0, 0];
            println!("calldata: {calldata:?}");
            match library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()) {
                Result::Ok(result) => result,
                Result::Err(_err) => panic(array!['just failed']),
            }
            // array![42, 69].span()
        }
    }
}
