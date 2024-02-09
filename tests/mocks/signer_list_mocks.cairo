#[starknet::contract]
mod SignerListMock {
    use argent::signer::signer_list::signer_list_component;

    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    #[abi(embed_v0)]
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SignerListEvents: signer_list_component::Event,
    }
}
