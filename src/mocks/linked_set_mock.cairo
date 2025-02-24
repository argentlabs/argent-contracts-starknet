/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes.
/// Please refrain from relying on the functionality of this contract for any production code. 🚨
///

#[starknet::component]
pub mod linked_set_mock {
    use argent::linked_set::linked_set::LinkedSet;
    use argent::linked_set::linked_set_with_head::LinkedSetWithHead;
    use argent::signer::signer_signature::SignerStorageValue;

    #[storage]
    pub struct Storage {
        pub linked_set_with_head: LinkedSetWithHead<SignerStorageValue>,
        pub linked_set: LinkedSet<SignerStorageValue>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}
}
